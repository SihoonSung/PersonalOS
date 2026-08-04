import Foundation
import SwiftData
import Observation
#if canImport(UserNotifications)
import UserNotifications
#endif

// MARK: - Mail → 가계부
//
// One pass: connect over IMAP, search each enabled source's sender since the
// last run, fetch what's new, parse it, and write the hits into the 가계부
// database as unreviewed entries. Message-ID is the dedupe key, so re-running
// a wider window (or syncing from a second device) never doubles anything.

@Observable
final class MailSyncService {

    static let shared = MailSyncService()

    struct SyncResult {
        var imported = 0
        var skipped = 0
        var scanned = 0
        /// Alerts that carry an amount but matched no rule — a hint that the
        /// bank changed wording or a new alert type was switched on.
        var unrecognized = 0
        /// The same incoming money reported by two different alert types.
        var merged = 0
        var finishedAt = Date.now
        var errorMessage: String?

        var summary: String {
            if let errorMessage { return errorMessage }
            var text = imported == 0
                ? "새 거래가 없어요 (\(scanned)통 확인)"
                : "\(imported)건 추가 · \(scanned)통 확인"
            if merged > 0 { text += " · 중복 \(merged)건 제외" }
            if unrecognized > 0 { text += " · 못 읽은 알림 \(unrecognized)통" }
            return text
        }
    }

    private(set) var isSyncing = false
    private(set) var progressText = ""
    private(set) var lastResult: SyncResult?

    private var container: ModelContainer?

    private init() {}

    func configure(container: ModelContainer) {
        self.container = container
    }

    // MARK: Connection test

    /// Logs in, opens the mailbox and reports what it found, without importing
    /// anything. Used by the settings screen's "연결 테스트" button.
    func testConnection(address: String, password: String) async -> String {
        let client = IMAPClient(
            host: MailSettings.host,
            port: MailSettings.port,
            username: address,
            password: password
        )
        do {
            try await client.connect()
            try await client.login()
            let mailbox = MailSettings.mailbox.isEmpty ? await client.allMailMailbox() : MailSettings.mailbox
            try await client.examine(mailbox)

            let since = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
            var found = 0
            for source in MailSource.allCases where MailSettings.isEnabled(source.id) {
                for sender in source.searchSenders {
                    found += (try? await client.searchUIDs(from: sender, since: since))?.count ?? 0
                }
            }
            await client.logout()
            return "연결 성공 — \(mailbox)에서 최근 2주 알림 \(found)통을 찾았어요."
        } catch {
            client.disconnect()
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: Sync

    /// Foreground entry point. Throttled so bouncing in and out of the app
    /// doesn't hammer Gmail — the alerts aren't going anywhere.
    func syncIfDue(minimumInterval: TimeInterval = 5 * 60) async {
        guard MailSettings.autoSync, MailSettings.isConfigured, !isSyncing else { return }
        if let last = MailSettings.lastSyncAt, Date.now.timeIntervalSince(last) < minimumInterval { return }
        await syncNow()
    }

    @discardableResult
    func syncNow(force: Bool = false) async -> SyncResult {
        guard !isSyncing else { return lastResult ?? SyncResult() }
        guard MailSettings.isConfigured else {
            let result = SyncResult(errorMessage: "설정에서 Gmail 주소와 앱 비밀번호를 먼저 입력해 주세요.")
            lastResult = result
            return result
        }
        guard let container else {
            let result = SyncResult(errorMessage: "데이터베이스가 아직 준비되지 않았어요.")
            lastResult = result
            return result
        }

        isSyncing = true
        progressText = "메일 서버에 연결 중…"
        defer {
            isSyncing = false
            progressText = ""
        }

        let context = container.mainContext
        guard let budget = budgetDatabase(in: context) else {
            let result = SyncResult(errorMessage: "가계부 데이터베이스를 찾지 못했어요.")
            lastResult = result
            return result
        }

        let client = IMAPClient(
            host: MailSettings.host,
            port: MailSettings.port,
            username: MailSettings.address,
            password: MailSettings.password ?? ""
        )

        var result = SyncResult()
        let since = force
            ? (Calendar.current.date(byAdding: .day, value: -MailSettings.backfillDays, to: .now) ?? .now)
            : MailSettings.searchSince

        do {
            try await client.connect()
            try await client.login()
            let mailbox = MailSettings.mailbox.isEmpty ? await client.allMailMailbox() : MailSettings.mailbox
            try await client.examine(mailbox)

            var known = existingMessageIDs(in: context)
            var uids: [UInt32] = []
            for source in MailSource.allCases where MailSettings.isEnabled(source.id) {
                for sender in source.searchSenders {
                    uids.append(contentsOf: (try? await client.searchUIDs(from: sender, since: since)) ?? [])
                }
            }
            uids = Array(Set(uids)).sorted()

            var pending: [ParsedTransaction] = []
            for (index, uid) in uids.enumerated() {
                progressText = "메일 확인 중 \(index + 1)/\(uids.count)"
                await Task.yield()

                guard let raw = try? await client.fetchMessage(uid: uid) else { continue }
                result.scanned += 1

                let message = MIMEMessage.parse(raw.bytes)
                guard let transaction = TransactionParser.parse(message) else {
                    if TransactionParser.looksUnrecognized(message) { result.unrecognized += 1 }
                    continue
                }
                guard !transaction.messageID.isEmpty else { continue }
                guard !known.contains(transaction.messageID) else {
                    result.skipped += 1
                    continue
                }
                if isEcho(of: transaction, in: budget, alsoAgainst: pending) {
                    result.merged += 1
                    continue
                }
                known.insert(transaction.messageID)
                pending.append(transaction)
            }

            await client.logout()

            for transaction in pending {
                insert(transaction, into: budget, context: context)
                result.imported += 1
            }
            if result.imported > 0 {
                try? context.save()
                WidgetDataWriter.refresh(context: context)
                // 노션 연결된 가계부면 새 거래를 그쪽에도 올린다.
                NotionSyncService.shared.scheduleAutoSync()
            }

            MailSettings.lastSyncAt = .now
        } catch {
            client.disconnect()
            result.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        result.finishedAt = .now
        lastResult = result

        if result.imported > 0, MailSettings.notify {
            await notify(count: result.imported)
        }
        return result
    }

    // MARK: Writing entries

    private func budgetDatabase(in context: ModelContext) -> POSDatabase? {
        let all = (try? context.fetch(FetchDescriptor<POSDatabase>())) ?? []
        return all.first { $0.templateKey == TemplateKey.budget }
    }

    /// Every Message-ID already imported. Small enough to hold in memory —
    /// one string per imported transaction.
    private func existingMessageIDs(in context: ModelContext) -> Set<String> {
        let descriptor = FetchDescriptor<POSEntry>(
            predicate: #Predicate { $0.sourceMessageID != nil }
        )
        let entries = (try? context.fetch(descriptor)) ?? []
        return Set(entries.compactMap(\.sourceMessageID))
    }

    /// 같은 입금이 서로 다른 알림으로 두 번 오는 경우를 걸러낸다.
    ///
    /// Chase의 "Deposit of more than $X posted"는 Zelle 입금에도 걸릴 수 있어서,
    /// 같은 돈이 `chase.zelle-in`과 `chase.deposit` 두 메일로 들어온다.
    /// Message-ID가 달라 기본 중복 차단에 안 걸리므로 금액·시각으로 잡는다.
    ///
    /// 조건을 좁게 건 이유:
    /// - **들어온 돈만** 본다. 지출은 같은 금액이 하루에 여러 번 나오는 게
    ///   정상이다 (MTA 지하철 $3.00을 오전·오후에 두 번 찍는 식).
    /// - **규칙이 다를 때만** 병합한다. 같은 규칙이면 진짜 별개 거래다
    ///   (룸메 둘이 각자 $4.50씩 보낸 경우처럼).
    private func isEcho(
        of transaction: ParsedTransaction,
        in database: POSDatabase,
        alsoAgainst pending: [ParsedTransaction]
    ) -> Bool {
        guard EntryKind.sign(transaction.kind) > 0 else { return false }
        let window: TimeInterval = 36 * 60 * 60

        for other in pending
        where EntryKind.sign(other.kind) > 0
            && other.ruleID != transaction.ruleID
            && abs(other.amount - transaction.amount) < 0.005
            && abs(other.date.timeIntervalSince(transaction.date)) < window {
            return true
        }

        guard let amountProperty = database.amountProperty else { return false }
        for entry in database.entries ?? [] {
            guard entry.sourceKind == "email",
                  let rule = entry.sourceRule, rule != transaction.ruleID,
                  EntryKind.sign(entry.kind(in: database)) > 0,
                  let amount = entry.number(for: amountProperty),
                  abs(amount - transaction.amount) < 0.005,
                  abs(entry.effectiveDate(in: database).timeIntervalSince(transaction.date)) < window
            else { continue }
            return true
        }
        return false
    }

    private func insert(_ transaction: ParsedTransaction, into database: POSDatabase, context: ModelContext) {
        // Money coming in has no meaningful spending category — filing it
        // under 금융 keeps the category chart (지출만 집계) untouched.
        let category = EntryKind.countsAsSpending(transaction.kind)
            ? CategoryRules.category(for: transaction.merchantRaw, context: context)
            : "금융"
        let title = CategoryRules.displayName(
            for: transaction.merchantRaw,
            fallback: transaction.title,
            context: context
        )

        let entry = POSEntry(title: title)
        context.insert(entry)
        entry.database = database
        entry.sourceKind = "email"
        entry.sourceMessageID = transaction.messageID
        entry.sourceRule = transaction.ruleID

        if let property = database.amountProperty {
            entry.setNumber(transaction.amount, for: property, context: context)
        }
        if let property = database.dateProperty {
            entry.setDate(transaction.date, for: property, context: context)
        }
        if let property = database.categoryProperty {
            entry.setText(category, for: property, context: context)
        }
        if let property = database.kindProperty {
            entry.setText(transaction.kind, for: property, context: context)
        }
        if let property = database.methodProperty {
            entry.setText(transaction.method, for: property, context: context)
        }
        if let property = database.sourceProperty {
            let note = transaction.note.isEmpty ? "" : " · \(transaction.note)"
            entry.setText(transaction.merchantRaw + note, for: property, context: context)
        }
        if let property = database.reviewedProperty {
            entry.setBool(false, for: property, context: context)
        }
    }

    // MARK: Notification

    private func notify(count: Int) async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "새 거래 \(count)건"
        content.body = "가계부에 추가했어요. 검토 후 확인 표시해 주세요."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "mail-import-\(Int(Date.now.timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
        #endif
    }
}
