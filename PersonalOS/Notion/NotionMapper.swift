import Foundation
import SwiftData

// MARK: - Schema mapping
//
// Connects an app database's schema to an EXISTING Notion database's schema.
// Properties are matched by NAME (case/whitespace-insensitive) and validated
// by type. The app's built-in title maps to Notion's title property, whatever
// it happens to be named.

struct NotionPropertyLink: Identifiable {
    let appProperty: POSProperty
    let notionName: String
    let notionType: String
    let compatible: Bool

    var id: UUID { appProperty.uuid }
}

struct NotionMapping {
    /// Name of the Notion database's title property (e.g. "이름", "Name").
    let titleName: String
    /// App properties that found a same-named Notion property.
    let links: [NotionPropertyLink]
    /// App properties with no matching Notion property (skipped in sync).
    let unmatched: [POSProperty]
    /// Supported Notion properties with no same-named app property —
    /// importable via `alignSchema`.
    let notionOnly: [(name: String, type: String)]

    var compatibleLinks: [NotionPropertyLink] { links.filter(\.compatible) }

    /// True when "노션 속성에 맞추기" would change anything structural.
    var needsAlignment: Bool {
        !notionOnly.isEmpty || links.contains { !$0.compatible }
    }
}

enum NotionMapper {

    /// Notion property types each app type can sync with.
    static func compatibleNotionTypes(for type: PropertyType) -> Set<String> {
        switch type {
        case .text: return ["rich_text"]
        case .number: return ["number"]
        case .date: return ["date"]
        case .checkbox: return ["checkbox"]
        case .select: return ["select", "status"]
        case .multiSelect: return ["multi_select"]
        case .url: return ["url"]
        }
    }

    /// App property type for a Notion property type (nil = unsupported).
    static func appType(forNotionType type: String) -> PropertyType? {
        switch type {
        case "rich_text": return .text
        case "number": return .number
        case "date": return .date
        case "checkbox": return .checkbox
        case "select", "status": return .select
        case "multi_select": return .multiSelect
        case "url": return .url
        default: return nil
        }
    }

    /// Korean display name for a Notion property type.
    static func displayName(forNotionType type: String) -> String {
        switch type {
        case "rich_text": return "텍스트"
        case "number": return "숫자"
        case "date": return "날짜"
        case "checkbox": return "체크박스"
        case "select": return "선택"
        case "status": return "상태"
        case "multi_select": return "다중 선택"
        case "url": return "URL"
        default: return type
        }
    }

    private static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Builds the mapping from an app database to a Notion schema
    /// (the "properties" object of a Notion database).
    static func mapping(for database: POSDatabase, notionSchema: [String: Any]) -> NotionMapping {
        let notionProps = notionSchema["properties"] as? [String: Any] ?? [:]

        var titleName = "Name"
        var byNormalizedName: [String: (name: String, type: String)] = [:]
        for (name, def) in notionProps {
            guard let type = (def as? [String: Any])?["type"] as? String else { continue }
            if type == "title" { titleName = name }
            byNormalizedName[normalize(name)] = (name, type)
        }

        var links: [NotionPropertyLink] = []
        var unmatched: [POSProperty] = []
        var matchedNotionNames = Set<String>()
        for property in database.orderedProperties {
            if let match = byNormalizedName[normalize(property.name)], match.type != "title" {
                matchedNotionNames.insert(normalize(match.name))
                links.append(NotionPropertyLink(
                    appProperty: property,
                    notionName: match.name,
                    notionType: match.type,
                    compatible: compatibleNotionTypes(for: property.type).contains(match.type)
                ))
            } else {
                unmatched.append(property)
            }
        }

        let notionOnly: [(String, String)] = byNormalizedName.values
            .filter { $0.type != "title" }
            .filter { appType(forNotionType: $0.type) != nil }
            .filter { !matchedNotionNames.contains(normalize($0.name)) }
            .sorted { $0.name < $1.name }
            .map { ($0.name, $0.type) }

        return NotionMapping(titleName: titleName, links: links, unmatched: unmatched, notionOnly: notionOnly)
    }

    // MARK: - Schema alignment (Notion → app)

    /// Makes the app database's schema match the Notion database:
    /// creates missing properties, fixes incompatible types, and refreshes
    /// select options / number formats from Notion. App-only properties are
    /// left untouched (they simply stay out of sync).
    @MainActor
    static func alignSchema(of database: POSDatabase, notionSchema: [String: Any], context: ModelContext) {
        let notionProps = notionSchema["properties"] as? [String: Any] ?? [:]
        var nextIndex = (database.orderedProperties.map(\.sortIndex).max() ?? -1) + 1

        for (name, rawDef) in notionProps.sorted(by: { $0.key < $1.key }) {
            guard let def = rawDef as? [String: Any],
                  let notionType = def["type"] as? String,
                  notionType != "title",
                  let mappedType = appType(forNotionType: notionType)
            else { continue }

            if let existing = database.orderedProperties.first(where: { normalize($0.name) == normalize(name) }) {
                if !compatibleNotionTypes(for: existing.type).contains(notionType) {
                    existing.type = mappedType
                }
                refreshConfig(of: existing, from: def, notionType: notionType)
            } else {
                let property = POSProperty(name: name, type: mappedType, sortIndex: nextIndex)
                refreshConfig(of: property, from: def, notionType: notionType)
                property.database = database
                context.insert(property)
                nextIndex += 1
            }
        }
        try? context.save()
    }

    /// Copies option lists / number formats from a Notion property definition.
    private static func refreshConfig(of property: POSProperty, from def: [String: Any], notionType: String) {
        var config = property.config
        switch notionType {
        case "select", "status", "multi_select":
            let container = def[notionType] as? [String: Any]
            let options = (container?["options"] as? [[String: Any]])?
                .compactMap { $0["name"] as? String } ?? []
            if !options.isEmpty { config.selectOptions = options }

        case "number":
            let format = ((def["number"] as? [String: Any])?["format"] as? String) ?? "number"
            if let code = currencyCode(forNotionFormat: format) {
                config.numberFormat = .currency
                config.currencyCode = code
            } else {
                config.numberFormat = .plain
            }

        case "date":
            // Notion dates carry per-value time info; leave includeTime as-is.
            break

        default:
            break
        }
        property.config = config
    }

    // MARK: - Content identity (first-link matching & dedupe)

    /// A loose content fingerprint: title + amount + day. Entries/pages with
    /// the same key are treated as "the same thing" when neither side is
    /// linked yet, and as duplicates by the dedupe pass.
    static func contentKey(entry: POSEntry, database: POSDatabase) -> String {
        var parts = [entry.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
        if let property = database.amountProperty {
            parts.append(entry.number(for: property).map { String($0) } ?? "")
        }
        if let property = database.dateProperty {
            parts.append(entry.date(for: property).map(NotionDate.dayString) ?? "")
        }
        return parts.joined(separator: "|")
    }

    static func contentKey(page: [String: Any], mapping: NotionMapping, database: POSDatabase) -> String {
        var parts = [title(fromPage: page, mapping: mapping)
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
        let props = page["properties"] as? [String: Any] ?? [:]
        if let property = database.amountProperty {
            let link = mapping.compatibleLinks.first { $0.appProperty.uuid == property.uuid }
            let number = link.flatMap { (props[$0.notionName] as? [String: Any])?["number"] as? Double }
            parts.append(number.map { String($0) } ?? "")
        }
        if let property = database.dateProperty {
            let link = mapping.compatibleLinks.first { $0.appProperty.uuid == property.uuid }
            let start = link.flatMap {
                ((props[$0.notionName] as? [String: Any])?["date"] as? [String: Any])?["start"] as? String
            }
            parts.append(start.flatMap(NotionDate.parse).map(NotionDate.dayString) ?? "")
        }
        return parts.joined(separator: "|")
    }

    /// Keys that are all-empty (blank drafts) — excluded from matching/dedupe.
    static func isBlankKey(_ key: String) -> Bool {
        key.split(separator: "|", omittingEmptySubsequences: true).isEmpty
    }

    private static func currencyCode(forNotionFormat format: String) -> String? {
        switch format {
        case "dollar": return "USD"
        case "won": return "KRW"
        case "euro": return "EUR"
        case "yen": return "JPY"
        case "pound": return "GBP"
        case "canadian_dollar": return "CAD"
        case "australian_dollar": return "AUD"
        default: return nil
        }
    }

    // MARK: - Local → Notion (write payload)

    /// Full properties payload for creating/updating the entry's page.
    /// Empty local values are written as explicit nulls so clears propagate.
    static func pageProperties(for entry: POSEntry, mapping: NotionMapping) -> [String: Any] {
        var payload: [String: Any] = [
            mapping.titleName: ["title": [["text": ["content": entry.title]]]]
        ]
        for link in mapping.compatibleLinks {
            payload[link.notionName] = propertyValue(for: entry, link: link)
        }
        return payload
    }

    private static func propertyValue(for entry: POSEntry, link: NotionPropertyLink) -> [String: Any] {
        let property = link.appProperty
        switch property.type {
        case .text:
            let text = entry.text(for: property) ?? ""
            return ["rich_text": text.isEmpty ? [] : [["text": ["content": text]]]]

        case .number:
            if let n = entry.number(for: property) {
                return ["number": n]
            }
            return ["number": NSNull()]

        case .checkbox:
            return ["checkbox": entry.bool(for: property)]

        case .date:
            guard let d = entry.date(for: property) else { return ["date": NSNull()] }
            let start = property.config.includeTime
                ? NotionDate.isoString(d)
                : NotionDate.dayString(d)
            return ["date": ["start": start]]

        case .select:
            guard let name = entry.text(for: property), !name.isEmpty else {
                return [link.notionType: NSNull()]
            }
            // Notion auto-creates unknown select options; status options must
            // already exist (writing an unknown status fails — surfaced as a
            // sync error rather than silently dropped).
            return [link.notionType: ["name": name]]

        case .multiSelect:
            let list = entry.textList(for: property)
            return ["multi_select": list.map { ["name": $0] }]

        case .url:
            if let url = entry.text(for: property), !url.isEmpty {
                return ["url": url]
            }
            return ["url": NSNull()]
        }
    }

    // MARK: - Notion → Local (apply page)

    /// Title text from a page's properties.
    static func title(fromPage page: [String: Any], mapping: NotionMapping) -> String {
        let props = page["properties"] as? [String: Any] ?? [:]
        let titleProp = props[mapping.titleName] as? [String: Any]
        return NotionAPI.plainText(titleProp?["title"])
    }

    /// Applies every mapped property of a Notion page onto a local entry.
    @MainActor
    static func apply(
        page: [String: Any],
        to entry: POSEntry,
        mapping: NotionMapping,
        context: ModelContext
    ) {
        entry.title = title(fromPage: page, mapping: mapping)

        // 카테고리가 노션 쪽에서 바뀌어 내려왔는지 보려고 적용 전 값을 잡아둔다.
        let database = entry.database
        let categoryProperty = database?.categoryProperty
        let previousCategory = categoryProperty.flatMap { entry.text(for: $0) }

        let props = page["properties"] as? [String: Any] ?? [:]
        for link in mapping.compatibleLinks {
            guard let raw = props[link.notionName] as? [String: Any] else { continue }
            let property = link.appProperty
            switch property.type {
            case .text:
                let text = NotionAPI.plainText(raw["rich_text"])
                entry.setText(text.isEmpty ? nil : text, for: property, context: context)

            case .number:
                entry.setNumber(raw["number"] as? Double, for: property, context: context)

            case .checkbox:
                entry.setBool(raw["checkbox"] as? Bool ?? false, for: property, context: context)

            case .date:
                var date: Date?
                if let dict = raw["date"] as? [String: Any],
                   let start = dict["start"] as? String {
                    date = NotionDate.parse(start)
                }
                entry.setDate(date, for: property, context: context)

            case .select:
                let option = (raw[link.notionType] as? [String: Any])?["name"] as? String
                entry.setText(option, for: property, context: context)
                // Keep the app's option list in step with values seen in Notion.
                if let option, !option.isEmpty, !property.config.selectOptions.contains(option) {
                    var config = property.config
                    config.selectOptions.append(option)
                    property.config = config
                }

            case .multiSelect:
                let options = (raw["multi_select"] as? [[String: Any]])?
                    .compactMap { $0["name"] as? String } ?? []
                entry.setTextList(options, for: property, context: context)
                let unknown = options.filter { !property.config.selectOptions.contains($0) }
                if !unknown.isEmpty {
                    var config = property.config
                    config.selectOptions.append(contentsOf: unknown)
                    property.config = config
                }

            case .url:
                entry.setText(raw["url"] as? String, for: property, context: context)
            }
        }

        learnCategoryCorrection(
            entry: entry,
            database: database,
            categoryProperty: categoryProperty,
            previousCategory: previousCategory,
            context: context
        )
    }

    /// 노션에서 메일 거래의 카테고리를 사람이(또는 검증 루틴이) 고쳐 내려보내면,
    /// 그 가게를 다음부터 같은 카테고리로 넣도록 규칙을 학습한다.
    ///
    /// 이게 없으면 노션에서 고쳐도 앱이 같은 가게를 매번 똑같이 잘못 분류한다 —
    /// 고침이 영원히 반복된다.
    @MainActor
    private static func learnCategoryCorrection(
        entry: POSEntry,
        database: POSDatabase?,
        categoryProperty: POSProperty?,
        previousCategory: String?,
        context: ModelContext
    ) {
        // 메일로 들어온 항목만 — 손으로 적은 건 가게 문자열이 없어 일반화할 수 없다.
        guard entry.sourceKind == "email",
              let categoryProperty,
              let newCategory = entry.text(for: categoryProperty),
              !newCategory.isEmpty,
              newCategory != previousCategory,
              let sourceProperty = database?.sourceProperty,
              let rawSource = entry.text(for: sourceProperty),
              !rawSource.isEmpty
        else { return }

        // 출처 이메일은 "<가게 원문> · <메모>" 형태로 저장된다.
        let pattern = rawSource.components(separatedBy: " · ").first ?? rawSource
        CategoryRules.teach(pattern: pattern, category: newCategory, context: context)
    }
}
