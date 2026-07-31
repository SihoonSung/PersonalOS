import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(AppSettings.mcpEnabledKey) private var mcpEnabled = false
    @AppStorage(AppSettings.mcpPortKey) private var mcpPort = 4141
    @ObservedObject private var ai = AIService.shared
    @Query(sort: \POSDatabase.sortIndex) private var databases: [POSDatabase]
    @State private var showingNotionSettings = false

    var body: some View {
        Form {
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
                    ShareLink(
                        item: ExportService.json(for: db),
                        preview: SharePreview("\(db.name).json")
                    ) {
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
