import SwiftUI
import SwiftData

// MARK: - Notion sync settings (token + per-database links)

struct NotionSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \POSDatabase.sortIndex) private var databases: [POSDatabase]
    @ObservedObject private var sync = NotionSyncService.shared

    @State private var token = NotionSyncService.shared.storedToken
    @State private var connectionStatus: ConnectionStatus = .unknown

    enum ConnectionStatus: Equatable {
        case unknown, checking, ok(String), failed(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                tokenSection
                databasesSection
                syncSection
            }
            .formStyle(.grouped)
            .navigationTitle("Notion 동기화")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 480)
        #endif
    }

    // MARK: Token

    private var tokenSection: some View {
        Section {
            SecureField("ntn_ 또는 secret_으로 시작", text: $token)
                .onSubmit { saveToken() }
            HStack {
                Button("저장하고 연결 확인") { saveToken() }
                    .disabled(token.isEmpty)
                Spacer()
                switch connectionStatus {
                case .unknown:
                    EmptyView()
                case .checking:
                    ProgressView().controlSize(.small)
                case .ok(let name):
                    Label(name, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                case .failed(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Integration 토큰")
        } footer: {
            Text("notion.so/my-integrations에서 Internal Integration을 만들어 토큰을 붙여넣으세요. 연결할 노션 데이터베이스 페이지에서 ⋯ → 연결(Connections)에 이 Integration을 추가해야 목록에 나타나요.")
        }
    }

    private func saveToken() {
        sync.updateToken(token)
        guard !token.isEmpty else {
            connectionStatus = .unknown
            return
        }
        connectionStatus = .checking
        Task {
            do {
                let name = try await NotionAPI.shared.me()
                connectionStatus = .ok(name)
            } catch {
                connectionStatus = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: Database links

    private var databasesSection: some View {
        Section("데이터베이스 연결") {
            ForEach(databases) { db in
                NavigationLink {
                    NotionLinkView(database: db)
                } label: {
                    HStack {
                        Label {
                            Text(db.name)
                        } icon: {
                            Text(db.icon)
                        }
                        Spacer()
                        if db.notionSyncEnabled, db.notionDatabaseID != nil {
                            Text(db.notionDatabaseTitle ?? "연결됨")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("연결 안 됨")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: Sync status

    private var syncSection: some View {
        Section {
            Button {
                Task { await sync.syncAll() }
            } label: {
                HStack {
                    Label("지금 동기화", systemImage: "arrow.triangle.2.circlepath")
                    if sync.isSyncing {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(sync.isSyncing)

            if let at = sync.lastSyncAt {
                LabeledContent("마지막 동기화", value: at.formatted(.relative(presentation: .named)))
            } else {
                LabeledContent("마지막 동기화", value: "없음")
            }
            if sync.pendingArchiveCount > 0 {
                LabeledContent("반영 대기 중인 삭제", value: "\(sync.pendingArchiveCount)건")
            }
            if let error = sync.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } footer: {
            Text("항목을 저장하면 몇 초 뒤 자동으로 동기화돼요. 노션에서 바꾼 내용도 이때 함께 가져와요.")
        }
    }
}

// MARK: - Per-database link editor

struct NotionLinkView: View {
    @Environment(\.modelContext) private var context
    @Bindable var database: POSDatabase
    @ObservedObject private var sync = NotionSyncService.shared

    @State private var availableDatabases: [(id: String, title: String)] = []
    @State private var loadState: LoadState = .idle
    @State private var mapping: NotionMapping?
    @State private var isAligning = false
    @State private var dedupeResult: Int?

    enum LoadState: Equatable {
        case idle, loading, loaded, failed(String)
    }

    var body: some View {
        Form {
            pickerSection
            if database.notionDatabaseID != nil {
                mappingSection
                controlSection
            }
        }
        .formStyle(.grouped)
        .navigationTitle(database.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await loadDatabases() }
    }

    // MARK: Notion database picker

    private var pickerSection: some View {
        Section {
            switch loadState {
            case .loading:
                HStack {
                    ProgressView().controlSize(.small)
                    Text("노션 데이터베이스 불러오는 중...")
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                Button("다시 시도") { Task { await loadDatabases(force: true) } }
            default:
                Picker("노션 데이터베이스", selection: selectionBinding) {
                    Text("선택 안 함").tag("")
                    ForEach(availableDatabases, id: \.id) { item in
                        Text(item.title).tag(item.id)
                    }
                }
            }
        } footer: {
            Text("목록이 비어 있으면 노션에서 해당 데이터베이스 페이지에 Integration을 연결했는지 확인하세요.")
        }
    }

    private var selectionBinding: Binding<String> {
        Binding(
            get: { database.notionDatabaseID ?? "" },
            set: { newValue in
                if newValue.isEmpty {
                    database.notionDatabaseID = nil
                    database.notionDatabaseTitle = nil
                    database.notionSyncEnabled = false
                    mapping = nil
                } else {
                    database.notionDatabaseID = newValue
                    database.notionDatabaseTitle = availableDatabases.first { $0.id == newValue }?.title
                    // Linking to a different Notion DB invalidates old page links.
                    (database.entries ?? []).forEach {
                        $0.notionPageID = nil
                        $0.notionSyncedAt = nil
                        $0.notionLastEditedAt = nil
                    }
                    Task { await loadMapping() }
                }
                try? context.save()
            }
        )
    }

    // MARK: Property mapping preview

    private var mappingSection: some View {
        Section {
            if let mapping {
                mappingRow(
                    icon: "textformat",
                    name: "제목",
                    detail: "노션 \"\(mapping.titleName)\"",
                    detailStyle: .normal
                )
                ForEach(mapping.links) { link in
                    mappingRow(
                        icon: link.appProperty.type.systemImage,
                        name: link.appProperty.name,
                        detail: link.compatible
                            ? NotionMapper.displayName(forNotionType: link.notionType)
                            : "타입 불일치 (\(link.appProperty.type.displayName) ↔ \(NotionMapper.displayName(forNotionType: link.notionType)))",
                        detailStyle: link.compatible ? .normal : .warning
                    )
                }
                ForEach(mapping.notionOnly, id: \.name) { item in
                    mappingRow(
                        icon: "plus.circle.dashed",
                        name: item.name,
                        detail: "노션에만 있음 · \(NotionMapper.displayName(forNotionType: item.type))",
                        detailStyle: .muted
                    )
                }
                ForEach(mapping.unmatched, id: \.uuid) { property in
                    mappingRow(
                        icon: property.type.systemImage,
                        name: property.name,
                        detail: "앱에만 있음 · 동기화 제외",
                        detailStyle: .muted
                    )
                }
                if mapping.needsAlignment {
                    Button {
                        Task { await alignSchema() }
                    } label: {
                        Label("노션 속성에 맞추기", systemImage: "arrow.triangle.merge")
                    }
                    .disabled(isAligning)
                }
            } else {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("속성 매핑 확인 중...")
                        .foregroundStyle(.secondary)
                }
                .task { await loadMapping() }
            }
        } header: {
            Text("속성 매핑")
        } footer: {
            if let mapping, mapping.needsAlignment {
                Text("\"노션 속성에 맞추기\"를 누르면 노션에만 있는 속성을 앱에 만들고, 선택 옵션과 통화 형식도 노션과 동일하게 맞춰요. 앱에만 있는 속성은 그대로 둬요.")
            } else {
                Text("이름이 같은 속성끼리 동기화돼요.")
            }
        }
    }

    private enum DetailStyle { case normal, warning, muted }

    private func mappingRow(icon: String, name: String, detail: String, detailStyle: DetailStyle) -> some View {
        Label {
            HStack {
                Text(name)
                    .foregroundStyle(detailStyle == .muted ? .secondary : .primary)
                Spacer()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(detailStyle == .warning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
        }
    }

    private func alignSchema() async {
        guard let id = database.notionDatabaseID else { return }
        isAligning = true
        defer { isAligning = false }
        do {
            let schema = try await NotionAPI.shared.database(id: id)
            NotionMapper.alignSchema(of: database, notionSchema: schema, context: context)
            mapping = NotionMapper.mapping(for: database, notionSchema: schema)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: Enable + manual sync

    private var controlSection: some View {
        Section {
            Toggle("동기화 켜기", isOn: $database.notionSyncEnabled)
                .onChange(of: database.notionSyncEnabled) {
                    try? context.save()
                    if database.notionSyncEnabled {
                        Task { await sync.syncNow(database) }
                    }
                }

            if database.notionSyncEnabled {
                Button {
                    Task { await sync.syncNow(database) }
                } label: {
                    HStack {
                        Label("지금 동기화", systemImage: "arrow.triangle.2.circlepath")
                        if sync.isSyncing {
                            Spacer()
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(sync.isSyncing)

                if let at = database.notionLastSyncAt {
                    LabeledContent("마지막 동기화", value: at.formatted(.relative(presentation: .named)))
                }

                Button {
                    dedupeResult = sync.dedupeLocal(database)
                } label: {
                    Label("중복 항목 정리", systemImage: "rectangle.stack.badge.minus")
                }
                if let dedupeResult {
                    Text(dedupeResult > 0
                         ? "중복 \(dedupeResult)개를 정리했어요. 노션 쪽 중복 페이지도 곧 함께 정리돼요."
                         : "중복 항목이 없어요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let error = sync.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: Loading

    private func loadDatabases(force: Bool = false) async {
        guard force || availableDatabases.isEmpty else { return }
        loadState = .loading
        do {
            availableDatabases = try await NotionAPI.shared.searchDatabases()
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func loadMapping() async {
        guard let id = database.notionDatabaseID else { return }
        do {
            let schema = try await NotionAPI.shared.database(id: id)
            mapping = NotionMapper.mapping(for: database, notionSchema: schema)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}
