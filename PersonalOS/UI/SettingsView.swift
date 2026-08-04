import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(AppSettings.mcpEnabledKey) private var mcpEnabled = false
    @AppStorage(AppSettings.mcpPortKey) private var mcpPort = 4141
    @ObservedObject private var ai = AIService.shared
    @Query(sort: \POSDatabase.sortIndex) private var databases: [POSDatabase]
    @State private var showingMailSettings = false
    @State private var showingNotionSettings = false
    @AppStorage(AppLock.enabledKey) private var appLockEnabled = false
    private let sync = MailSyncService.shared

    private var budgetDatabase: POSDatabase? {
        databases.first { $0.templateKey == TemplateKey.budget }
    }

    private func unreviewedCount(in database: POSDatabase) -> Int {
        guard let reviewed = database.reviewedProperty else { return 0 }
        return (database.entries ?? []).filter { $0.sourceKind == "email" && !$0.bool(for: reviewed) }.count
    }

    var body: some View {
        Form {
            Section {
                Button {
                    showingMailSettings = true
                } label: {
                    HStack {
                        Label("메일 가계부", systemImage: "envelope.arrow.triangle.branch")
                        Spacer()
                        Text(MailSettings.isConfigured ? "켜짐" : "꺼짐")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                if MailSettings.isConfigured {
                    Button {
                        Task { await sync.syncNow() }
                    } label: {
                        HStack {
                            Label("지금 가져오기", systemImage: "arrow.down.circle")
                            Spacer()
                            if sync.isSyncing {
                                Text(sync.progressText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(sync.isSyncing)

                    if let result = sync.lastResult {
                        Text(result.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let budget = budgetDatabase {
                    NavigationLink {
                        ReviewQueueView(database: budget)
                    } label: {
                        HStack {
                            Label("검토 대기", systemImage: "tray.full")
                            Spacer()
                            Text("\(unreviewedCount(in: budget))건")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("가계부")
            } footer: {
                Text("Chase 알림 메일을 읽어서 가계부에 자동으로 넣어요. 메일은 읽기만 하고 건드리지 않습니다.")
            }

            Section {
                Button {
                    showingNotionSettings = true
                } label: {
                    HStack {
                        Label("Notion 동기화", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        Text(databases.contains { $0.notionSyncEnabled } ? "켜짐" : "꺼짐")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Text("Notion")
            } footer: {
                Text("데이터베이스별로 노션과 양방향 동기화할 수 있어요. 연결하지 않으면 이 기기와 iCloud에만 저장됩니다.")
            }

            Section {
                Toggle("앱 잠금", isOn: $appLockEnabled)
                    .onChange(of: appLockEnabled) {
                        AppLock.isEnabled = appLockEnabled
                        if appLockEnabled { AppLock.shared.lockNow() }
                    }
                    .disabled(!AppLock.isAvailable)
            } header: {
                Text("보안")
            } footer: {
                if AppLock.isAvailable {
                    Text("앱을 열 때 \(AppLock.biometryName)로 확인해요. 잠깐 다른 앱에 다녀오는 정도(1분 이내)로는 다시 묻지 않습니다.")
                } else {
                    Text("이 기기에 잠금 암호가 설정돼 있지 않아 앱 잠금을 쓸 수 없어요.")
                }
            }

            if let budget = budgetDatabase {
                Section {
                    NavigationLink {
                        RecurringView(database: budget)
                    } label: {
                        Label("고정지출", systemImage: "arrow.trianglehead.2.clockwise")
                    }
                }
            }

            Section {
                LabeledContent("온디바이스 AI", value: ai.isAvailable ? "사용 가능" : "사용 불가")
            } header: {
                Text("AI")
            } footer: {
                if !ai.isAvailable {
                    Text("온디바이스 AI를 사용할 수 없어 규칙 기반 파싱을 사용합니다.")
                }
            }

            #if os(macOS)
            Section {
                Toggle("MCP 서버 켜기", isOn: $mcpEnabled)
                    .onChange(of: mcpEnabled) {
                        if mcpEnabled {
                            MCPServer.shared.start(port: mcpPort)
                        } else {
                            MCPServer.shared.stop()
                        }
                    }
                if mcpEnabled {
                    LabeledContent("포트", value: "\(mcpPort)")
                    LabeledContent("엔드포인트", value: "http://127.0.0.1:\(mcpPort)/mcp")
                    Text("Claude 등 AI 에이전트에서 위 주소를 MCP 서버(HTTP)로 등록하면 데이터베이스를 읽고 쓸 수 있어요. 이 Mac에서만 접근 가능합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("AI 에이전트 연동 (MCP)")
            }
            #endif

            Section("데이터 내보내기") {
                ForEach(databases) { db in
                    NavigationLink {
                        ExportDatabaseView(database: db)
                    } label: {
                        Label("\(db.icon) \(db.name) — JSON", systemImage: "square.and.arrow.up")
                    }
                }
            }

            Section("동기화") {
                Text("iCloud에 로그인돼 있고 iCloud 기능이 켜져 있으면 아이폰↔맥 자동 동기화됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingMailSettings) {
            MailSettingsView()
        }
        .sheet(isPresented: $showingNotionSettings) {
            NotionSettingsView()
        }
        .navigationTitle("설정")
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 380)
        #endif
    }
}

// MARK: - Export

/// Serializing a database is O(entries × properties), so it happens here on
/// demand instead of inline in the settings list — that list re-renders on
/// every sync progress tick.
private struct ExportDatabaseView: View {
    let database: POSDatabase
    @State private var payload: String?

    var body: some View {
        Group {
            if let payload {
                VStack(spacing: Theme.spacingM) {
                    ShareLink(item: payload, preview: SharePreview("\(database.name).json")) {
                        Label("JSON 내보내기", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)

                    ScrollView {
                        Text(payload.prefix(4000))
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            } else {
                ProgressView()
            }
        }
        .navigationTitle("\(database.icon) \(database.name)")
        .task { payload = ExportService.json(for: database) }
    }
}

enum ExportService {

    /// Full database (schema + entries) as pretty JSON — the "other apps
    /// can read this" escape hatch alongside MCP.
    @MainActor
    static func json(for db: POSDatabase) -> String {
        var payload: [String: Any] = [
            "database": db.name,
            "template_key": db.templateKey,
            "exported_at": ISO8601DateFormatter().string(from: .now),
        ]
        payload["schema"] = db.orderedProperties.map { property -> [String: Any] in
            var item: [String: Any] = ["name": property.name, "type": property.type.rawValue]
            if property.type == .select { item["options"] = property.config.selectOptions }
            return item
        }
        payload["entries"] = (db.entries ?? [])
            .sorted { $0.createdAt > $1.createdAt }
            .map { entry -> [String: Any] in
                var item: [String: Any] = [
                    "id": entry.uuid.uuidString,
                    "title": entry.title,
                    "created_at": ISO8601DateFormatter().string(from: entry.createdAt),
                ]
                var values: [String: Any] = [:]
                for property in db.orderedProperties {
                    if let v = entry.jsonValue(for: property) { values[property.name] = v }
                }
                item["values"] = values
                return item
            }

        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
