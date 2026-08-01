#if os(macOS)
import Foundation
import SwiftData

/// MCP tool definitions + execution against the SwiftData store.
enum MCPTools {

    struct ToolError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func errorResult(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": message]], "isError": true]
    }

    // MARK: - Definitions (tools/list)

    static let definitions: [[String: Any]] = [
        [
            "name": "list_databases",
            "description": "사용자의 모든 데이터베이스 목록 (이름, 아이콘, 항목 수, 템플릿 키)을 반환합니다.",
            "inputSchema": ["type": "object", "properties": [:] as [String: Any]],
        ],
        [
            "name": "get_schema",
            "description": "데이터베이스의 속성(컬럼) 스키마를 반환합니다.",
            "inputSchema": [
                "type": "object",
                "properties": ["database": ["type": "string", "description": "데이터베이스 이름 또는 템플릿 키 (budget/todo)"]],
                "required": ["database"],
            ],
        ],
        [
            "name": "query_entries",
            "description": "데이터베이스의 항목을 조회합니다. 텍스트 검색과 개수 제한을 지원합니다.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "database": ["type": "string", "description": "데이터베이스 이름 또는 템플릿 키"],
                    "search": ["type": "string", "description": "제목/텍스트 값 검색어 (선택)"],
                    "limit": ["type": "integer", "description": "최대 개수 (기본 50)"],
                ],
                "required": ["database"],
            ],
        ],
        [
            "name": "create_entry",
            "description": "새 항목을 추가합니다. values는 {\"속성이름\": 값} 형태이며, 날짜는 yyyy-MM-dd 또는 ISO8601 문자열입니다.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "database": ["type": "string"],
                    "title": ["type": "string"],
                    "values": ["type": "object", "description": "{속성이름: 값}"],
                ],
                "required": ["database", "title"],
            ],
        ],
        [
            "name": "update_entry",
            "description": "기존 항목을 수정합니다. entry_id는 query_entries가 반환한 id입니다.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "entry_id": ["type": "string"],
                    "title": ["type": "string"],
                    "values": ["type": "object"],
                ],
                "required": ["entry_id"],
            ],
        ],
        [
            "name": "delete_entry",
            "description": "항목을 삭제합니다.",
            "inputSchema": [
                "type": "object",
                "properties": ["entry_id": ["type": "string"]],
                "required": ["entry_id"],
            ],
        ],
    ]

    // MARK: - Execution (tools/call)

    @MainActor
    static func execute(name: String, args: [String: Any], context: ModelContext) throws -> String {
        switch name {
        case "list_databases": return try listDatabases(context: context)
        case "get_schema": return try getSchema(args: args, context: context)
        case "query_entries": return try queryEntries(args: args, context: context)
        case "create_entry": return try createEntry(args: args, context: context)
        case "update_entry": return try updateEntry(args: args, context: context)
        case "delete_entry": return try deleteEntry(args: args, context: context)
        default: throw ToolError(message: "알 수 없는 도구: \(name)")
        }
    }

    // MARK: Tools

    @MainActor
    private static func listDatabases(context: ModelContext) throws -> String {
        let databases = try context.fetch(FetchDescriptor<POSDatabase>(sortBy: [SortDescriptor(\.sortIndex)]))
        let payload = databases.map { db in
            [
                "name": db.name,
                "icon": db.icon,
                "template_key": db.templateKey,
                "entry_count": db.entryCount,
            ] as [String: Any]
        }
        return jsonString(payload)
    }

    @MainActor
    private static func getSchema(args: [String: Any], context: ModelContext) throws -> String {
        let db = try findDatabase(args["database"] as? String, context: context)
        let payload = db.orderedProperties.map { property -> [String: Any] in
            var item: [String: Any] = [
                "name": property.name,
                "type": property.type.rawValue,
            ]
            let config = property.config
            if property.type == .select { item["options"] = config.selectOptions }
            if property.type == .number, config.numberFormat == .currency {
                item["currency"] = config.currencyCode
            }
            return item
        }
        return jsonString(["database": db.name, "title_field": "title", "properties": payload])
    }

    @MainActor
    private static func queryEntries(args: [String: Any], context: ModelContext) throws -> String {
        let db = try findDatabase(args["database"] as? String, context: context)
        let limit = min(args["limit"] as? Int ?? 50, 500)
        let search = (args["search"] as? String)?.lowercased()

        var entries = (db.entries ?? []).sorted { $0.createdAt > $1.createdAt }
        if let search, !search.isEmpty {
            entries = entries.filter { entry in
                if entry.title.lowercased().contains(search) { return true }
                return (entry.values ?? []).contains { $0.textValue?.lowercased().contains(search) == true }
            }
        }

        let payload = entries.prefix(limit).map { entry -> [String: Any] in
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
        return jsonString(Array(payload))
    }

    @MainActor
    private static func createEntry(args: [String: Any], context: ModelContext) throws -> String {
        let db = try findDatabase(args["database"] as? String, context: context)
        let entry = POSEntry(title: args["title"] as? String ?? "")
        entry.database = db
        context.insert(entry)
        try applyValues(args["values"] as? [String: Any] ?? [:], to: entry, in: db, context: context)
        try context.save()
        return jsonString(["ok": true, "id": entry.uuid.uuidString])
    }

    @MainActor
    private static func updateEntry(args: [String: Any], context: ModelContext) throws -> String {
        let entry = try findEntry(args["entry_id"] as? String, context: context)
        guard let db = entry.database else { throw ToolError(message: "항목의 데이터베이스를 찾을 수 없습니다.") }
        if let title = args["title"] as? String { entry.title = title }
        try applyValues(args["values"] as? [String: Any] ?? [:], to: entry, in: db, context: context)
        entry.touch()
        try context.save()
        return jsonString(["ok": true])
    }

    @MainActor
    private static func deleteEntry(args: [String: Any], context: ModelContext) throws -> String {
        let entry = try findEntry(args["entry_id"] as? String, context: context)
        context.delete(entry)
        try context.save()
        return jsonString(["ok": true])
    }

    // MARK: Helpers

    @MainActor
    private static func findDatabase(_ nameOrKey: String?, context: ModelContext) throws -> POSDatabase {
        guard let nameOrKey, !nameOrKey.isEmpty else {
            throw ToolError(message: "database 인자가 필요합니다.")
        }
        let databases = try context.fetch(FetchDescriptor<POSDatabase>())
        if let match = databases.first(where: { $0.name == nameOrKey || $0.templateKey == nameOrKey }) {
            return match
        }
        let available = databases.map(\.name).joined(separator: ", ")
        throw ToolError(message: "데이터베이스를 찾을 수 없습니다: \(nameOrKey). 사용 가능: \(available)")
    }

    @MainActor
    private static func findEntry(_ idString: String?, context: ModelContext) throws -> POSEntry {
        guard let idString, let uuid = UUID(uuidString: idString) else {
            throw ToolError(message: "유효한 entry_id가 필요합니다.")
        }
        let descriptor = FetchDescriptor<POSEntry>(predicate: #Predicate { $0.uuid == uuid })
        guard let entry = try context.fetch(descriptor).first else {
            throw ToolError(message: "항목을 찾을 수 없습니다: \(idString)")
        }
        return entry
    }

    @MainActor
    private static func applyValues(
        _ values: [String: Any],
        to entry: POSEntry,
        in db: POSDatabase,
        context: ModelContext
    ) throws {
        for property in db.orderedProperties {
            guard let raw = values[property.name] else { continue }
            switch property.type {
            case .text, .url:
                entry.setText(raw as? String, for: property, context: context)
            case .select:
                if let s = raw as? String {
                    if !s.isEmpty && !property.config.selectOptions.contains(s) {
                        throw ToolError(message: "\"\(property.name)\" 옵션이 아닙니다: \(s). 가능: \(property.config.selectOptions.joined(separator: ", "))")
                    }
                    entry.setText(s.isEmpty ? nil : s, for: property, context: context)
                }
            case .multiSelect:
                var list: [String] = []
                if let arr = raw as? [Any] {
                    list = arr.compactMap { $0 as? String }
                } else if let s = raw as? String, !s.isEmpty {
                    list = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                }
                let invalid = list.filter { !property.config.selectOptions.contains($0) }
                guard invalid.isEmpty else {
                    throw ToolError(message: "\"\(property.name)\" 옵션이 아닙니다: \(invalid.joined(separator: ", ")). 가능: \(property.config.selectOptions.joined(separator: ", "))")
                }
                entry.setTextList(list, for: property, context: context)
            case .number:
                if let n = raw as? Double { entry.setNumber(n, for: property, context: context) }
                else if let n = raw as? Int { entry.setNumber(Double(n), for: property, context: context) }
            case .checkbox:
                if let b = raw as? Bool { entry.setBool(b, for: property, context: context) }
            case .date:
                if let s = raw as? String {
                    guard let d = NaturalDateParser.parseFlexible(s) else {
                        throw ToolError(message: "\"\(property.name)\" 날짜 형식을 해석할 수 없습니다: \(s)")
                    }
                    entry.setDate(d, for: property, context: context)
                }
            }
        }
    }

    private static func jsonString(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
#endif
