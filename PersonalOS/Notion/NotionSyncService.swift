import Foundation
import Combine
import SwiftData

// MARK: - Two-way Notion sync
//
// Sync model (per linked database, per run):
//   1. Flush pending page archives (local deletions, incl. offline ones).
//   2. Fetch the Notion schema → build the name-based property mapping.
//   3. Fetch a FULL page listing (personal scale) → index by page ID.
//   4. For each pair, decide push / pull / conflict:
//        push  iff  entry.updatedAt        > entry.notionSyncedAt
//        pull  iff  page.last_edited_time  > entry.notionLastEditedAt
//        both → conflict → the more recently edited side wins.
//      After any push or pull both markers are refreshed, which is what
//      prevents echo loops (a push bumps last_edited_time remotely, but we
//      record the new value; a pull touches updatedAt locally, but we record
//      notionSyncedAt right after).
//   5. Remote pages with no local match → new local entries.
//      Local entries whose page vanished remotely → deleted in Notion:
//      locally-unmodified entries are deleted, locally-modified ones are
//      re-pushed as new pages (never lose local edits).
@MainActor
final class NotionSyncService: ObservableObject {

    static let shared = NotionSyncService()

    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastSyncAt: Date?
    /// 아직 노션에 반영 못 한 삭제 건수 (오프라인/실패로 밀린 것).
    @Published private(set) var pendingArchiveCount = 0

    private var container: ModelContainer?
    private var autoSyncTask: Task<Void, Never>?

    private let pendingArchiveKey = "notion.pendingArchivePageIDs"
    private let lastSyncAtKey = "notion.lastSyncAt"

    /// 마지막 성공이 이보다 오래됐으면 "지연"으로 본다. 자동 동기화가 3초
    /// 디바운스로 도니까, 몇 시간씩 성공이 없다는 건 뭔가 막혔다는 뜻이다.
    private let staleAfter: TimeInterval = 6 * 60 * 60

    /// 지금 동기화가 건강한지 — 대시보드 배지가 이걸 본다.
    enum Health: Equatable {
        case idle          // 연결된 DB 없음 / 토큰 없음 → 아무것도 표시하지 않는다
        case ok
        case syncing
        case stale(Date?)  // 마지막 성공이 오래됨
        case failing(String)
    }

    /// `linkedCount`는 뷰가 @Query로 세어 넘긴다 (서비스가 컨텍스트를 다시
    /// 읽으면 뷰 갱신과 어긋난다).
    func health(linkedCount: Int) -> Health {
        guard linkedCount > 0, !storedToken.isEmpty else { return .idle }
        if let lastError, !lastError.isEmpty { return .failing(lastError) }
        if isSyncing { return .syncing }
        guard let lastSyncAt else { return .stale(nil) }
        return Date.now.timeIntervalSince(lastSyncAt) > staleAfter ? .stale(lastSyncAt) : .ok
    }

    // MARK: Setup

    func configure(container: ModelContainer) {
        self.container = container
        // 앱을 껐다 켜도 "마지막 성공"이 남아 있어야 지연 판정이 가능하다.
        if let stored = UserDefaults.standard.object(forKey: lastSyncAtKey) as? Date {
            lastSyncAt = stored
        }
        refreshPendingCount()
        Task { await NotionAPI.shared.setToken(KeychainStore.get(KeychainStore.notionTokenKey)) }
    }

    private func refreshPendingCount() {
        pendingArchiveCount = (UserDefaults.standard.stringArray(forKey: pendingArchiveKey) ?? []).count
    }

    private func markSyncSucceeded() {
        lastSyncAt = .now
        UserDefaults.standard.set(lastSyncAt, forKey: lastSyncAtKey)
        refreshPendingCount()
    }

    func updateToken(_ token: String) {
        if token.isEmpty {
            KeychainStore.delete(KeychainStore.notionTokenKey)
        } else {
            KeychainStore.set(token, key: KeychainStore.notionTokenKey)
        }
        Task { await NotionAPI.shared.setToken(token.isEmpty ? nil : token) }
    }

    var storedToken: String { KeychainStore.get(KeychainStore.notionTokenKey) ?? "" }

    // MARK: Deletion hook

    /// Call BEFORE deleting a synced entry so its Notion page gets archived
    /// on the next sync run (survives offline / app restarts via UserDefaults).
    func entryWillDelete(_ entry: POSEntry) {
        guard let pageID = entry.notionPageID else { return }
        var pending = UserDefaults.standard.stringArray(forKey: pendingArchiveKey) ?? []
        if !pending.contains(pageID) {
            pending.append(pageID)
            UserDefaults.standard.set(pending, forKey: pendingArchiveKey)
        }
        refreshPendingCount()
        scheduleAutoSync()
    }

    // MARK: Triggers

    /// Debounced auto-sync — call after any local save.
    func scheduleAutoSync(after seconds: Double = 3) {
        autoSyncTask?.cancel()
        autoSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.syncAll()
        }
    }

    /// Syncs every linked & enabled database. Errors are collected, not thrown.
    func syncAll() async {
        guard let container, !isSyncing else { return }
        guard await NotionAPI.shared.hasToken else { return }

        let context = container.mainContext
        let databases = (try? context.fetch(FetchDescriptor<POSDatabase>())) ?? []
        let linked = databases.filter { $0.notionSyncEnabled && $0.notionDatabaseID != nil }
        guard !linked.isEmpty else { return }

        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        await flushPendingArchives()

        var errors: [String] = []
        for database in linked {
            do {
                try await sync(database: database, context: context)
            } catch {
                errors.append("\(database.name): \(error.localizedDescription)")
            }
        }
        lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
        if errors.isEmpty {
            markSyncSucceeded()
        } else {
            refreshPendingCount()
        }
    }

    /// Manual sync for a single database (used by the per-database UI).
    func syncNow(_ database: POSDatabase) async {
        guard let container, !isSyncing else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        await flushPendingArchives()
        do {
            try await sync(database: database, context: container.mainContext)
            markSyncSucceeded()
        } catch {
            lastError = "\(database.name): \(error.localizedDescription)"
            refreshPendingCount()
        }
    }

    // MARK: Core sync

    private func sync(database: POSDatabase, context: ModelContext) async throws {
        guard let notionDatabaseID = database.notionDatabaseID else { return }

        let schema = try await NotionAPI.shared.database(id: notionDatabaseID)
        let mapping = NotionMapper.mapping(for: database, notionSchema: schema)

        let pages = try await NotionAPI.shared.allPages(databaseID: notionDatabaseID)
        var pagesByID: [String: [String: Any]] = [:]
        for page in pages {
            if let id = page["id"] as? String { pagesByID[id] = page }
        }

        let entries = database.entries ?? []
        var seenPageIDs = Set<String>(entries.compactMap(\.notionPageID))

        // --- First-link content matching -------------------------------
        // Unlinked local entries that have a same-content remote page get
        // LINKED to it instead of being pushed as new pages (and the page
        // is then not pulled as a new entry). Prevents duplicates when both
        // sides already contained the same data before linking.
        let unlinkedEntries = entries.filter { $0.notionPageID == nil }
        if !unlinkedEntries.isEmpty {
            var pageIDsByKey: [String: [String]] = [:]
            for (pageID, page) in pagesByID where !seenPageIDs.contains(pageID) {
                let key = NotionMapper.contentKey(page: page, mapping: mapping, database: database)
                guard !NotionMapper.isBlankKey(key) else { continue }
                pageIDsByKey[key, default: []].append(pageID)
            }
            for entry in unlinkedEntries {
                let key = NotionMapper.contentKey(entry: entry, database: database)
                guard !NotionMapper.isBlankKey(key),
                      var candidates = pageIDsByKey[key],
                      let pageID = candidates.popLast()
                else { continue }
                pageIDsByKey[key] = candidates
                entry.notionPageID = pageID
                seenPageIDs.insert(pageID)
                if let page = pagesByID[pageID] {
                    // Notion is authoritative at first link.
                    NotionMapper.apply(page: page, to: entry, mapping: mapping, context: context)
                    markSynced(entry, page: page)
                }
            }
        }

        // --- Main reconcile loop ----------------------------------------
        for entry in entries {
            if let pageID = entry.notionPageID {
                if let page = pagesByID[pageID] {
                    try await reconcile(entry: entry, page: page, mapping: mapping, context: context)
                } else {
                    // Page deleted/archived in Notion.
                    let locallyModified = entry.updatedAt > (entry.notionSyncedAt ?? .distantPast)
                    if locallyModified {
                        entry.notionPageID = nil // re-push below as a new page
                        try await push(entry: entry, databaseID: notionDatabaseID, mapping: mapping)
                    } else {
                        entry.values?.forEach { context.delete($0) }
                        context.delete(entry)
                    }
                }
            } else {
                // Never synced → create remotely.
                try await push(entry: entry, databaseID: notionDatabaseID, mapping: mapping)
            }
        }

        // Remote pages with no local counterpart → new local entries.
        for (pageID, page) in pagesByID where !seenPageIDs.contains(pageID) {
            let entry = POSEntry()
            entry.database = database
            context.insert(entry)
            if let created = page["created_time"] as? String,
               let date = NotionDate.parse(created) {
                entry.createdAt = date
            }
            NotionMapper.apply(page: page, to: entry, mapping: mapping, context: context)
            markSynced(entry, page: page)
        }

        database.notionLastSyncAt = .now
        try context.save()
    }

    /// Push/pull/conflict decision for one linked entry–page pair.
    private func reconcile(
        entry: POSEntry,
        page: [String: Any],
        mapping: NotionMapping,
        context: ModelContext
    ) async throws {
        let remoteEdited = (page["last_edited_time"] as? String).flatMap(NotionDate.parse) ?? .distantPast
        let localChanged = entry.updatedAt > (entry.notionSyncedAt ?? .distantPast)
        let remoteChanged = remoteEdited > (entry.notionLastEditedAt ?? .distantPast)

        switch (localChanged, remoteChanged) {
        case (false, false):
            return
        case (true, false):
            try await push(entry: entry, databaseID: nil, mapping: mapping)
        case (false, true):
            NotionMapper.apply(page: page, to: entry, mapping: mapping, context: context)
            markSynced(entry, page: page)
        case (true, true):
            // Conflict: most recent edit wins.
            if entry.updatedAt >= remoteEdited {
                try await push(entry: entry, databaseID: nil, mapping: mapping)
            } else {
                NotionMapper.apply(page: page, to: entry, mapping: mapping, context: context)
                markSynced(entry, page: page)
            }
        }
    }

    /// Creates (databaseID != nil and no page ID) or updates the entry's page,
    /// then refreshes both sync markers from the response.
    private func push(entry: POSEntry, databaseID: String?, mapping: NotionMapping) async throws {
        let properties = NotionMapper.pageProperties(for: entry, mapping: mapping)
        let page: [String: Any]
        if let pageID = entry.notionPageID {
            page = try await NotionAPI.shared.updatePage(id: pageID, properties: properties)
        } else if let databaseID {
            page = try await NotionAPI.shared.createPage(databaseID: databaseID, properties: properties)
            entry.notionPageID = page["id"] as? String
        } else {
            return
        }
        markSynced(entry, page: page)
    }

    private func markSynced(_ entry: POSEntry, page: [String: Any]) {
        entry.notionSyncedAt = .now
        entry.notionLastEditedAt = (page["last_edited_time"] as? String).flatMap(NotionDate.parse)
    }

    // MARK: Dedupe

    /// Removes local duplicates (same title + amount + day), keeping one
    /// per group — preferring a Notion-linked entry, then the oldest.
    /// Deleted twins' Notion pages are archived on the next sync run, so
    /// this cleans BOTH sides. Returns the number of entries removed.
    func dedupeLocal(_ database: POSDatabase) -> Int {
        guard let container else { return 0 }
        let context = container.mainContext

        var groups: [String: [POSEntry]] = [:]
        for entry in database.entries ?? [] {
            let key = NotionMapper.contentKey(entry: entry, database: database)
            guard !NotionMapper.isBlankKey(key) else { continue }
            groups[key, default: []].append(entry)
        }

        var removed = 0
        for (_, group) in groups where group.count > 1 {
            let ranked = group.sorted { a, b in
                let aLinked = a.notionPageID != nil
                let bLinked = b.notionPageID != nil
                if aLinked != bLinked { return aLinked } // keep linked first
                return a.createdAt < b.createdAt        // then oldest
            }
            for extra in ranked.dropFirst() {
                entryWillDelete(extra)
                context.delete(extra)
                removed += 1
            }
        }
        if removed > 0 {
            try? context.save()
            scheduleAutoSync()
        }
        return removed
    }

    // MARK: Pending archives

    private func flushPendingArchives() async {
        let pending = UserDefaults.standard.stringArray(forKey: pendingArchiveKey) ?? []
        guard !pending.isEmpty else { return }
        var remaining: [String] = []
        for pageID in pending {
            do {
                try await NotionAPI.shared.archivePage(id: pageID)
            } catch let error as NotionAPIError where error.code == "object_not_found" {
                continue // already gone — drop it
            } catch {
                remaining.append(pageID) // retry next run
            }
        }
        UserDefaults.standard.set(remaining, forKey: pendingArchiveKey)
    }
}
