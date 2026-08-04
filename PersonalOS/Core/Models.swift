import Foundation
import SwiftData

// MARK: - PersonalOS Core Data Model
//
// Flexible, Notion-like database engine. Storage is local (SwiftData +
// CloudKit); Notion two-way sync is an opt-in layer enabled per database:
//   POSDatabase (a user-defined database, e.g. "가계부")
//     └─ POSProperty (column definition: 금액, 카테고리, ...)
//     └─ POSEntry (a row)
//          └─ POSValue (one cell: entry × property)
//
// CloudKit rules respected throughout:
//   - every stored attribute has a default value or is optional
//   - no @Attribute(.unique)
//   - all relationships optional, inverses declared on the "many" side

// MARK: - Property types

enum PropertyType: String, Codable, CaseIterable, Identifiable {
    case text
    case number
    case date
    case checkbox
    case select
    case multiSelect = "multiselect"
    case url

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .text: return "텍스트"
        case .number: return "숫자"
        case .date: return "날짜"
        case .checkbox: return "체크박스"
        case .select: return "선택"
        case .multiSelect: return "다중 선택"
        case .url: return "URL"
        }
    }

    var systemImage: String {
        switch self {
        case .text: return "textformat"
        case .number: return "number"
        case .date: return "calendar"
        case .checkbox: return "checkmark.square"
        case .select: return "tag"
        case .multiSelect: return "checklist"
        case .url: return "link"
        }
    }
}

/// Number display style for `.number` properties.
enum NumberFormat: String, Codable, CaseIterable, Identifiable {
    case plain
    case currency

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .plain: return "일반"
        case .currency: return "통화"
        }
    }
}

/// Per-property configuration, JSON-encoded into `POSProperty.configData`.
/// Kept as plain Codable so external readers (MCP, exports) see clean JSON.
struct PropertyConfig: Codable, Equatable {
    var selectOptions: [String] = []
    var numberFormat: NumberFormat = .plain
    var currencyCode: String = "KRW"
    var includeTime: Bool = false

    static let empty = PropertyConfig()

    static func decode(_ data: Data?) -> PropertyConfig {
        guard let data, !data.isEmpty,
              let config = try? JSONDecoder().decode(PropertyConfig.self, from: data)
        else { return .empty }
        return config
    }

    func encode() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }
}

// MARK: - Database

@Model
final class POSDatabase {
    var uuid: UUID = UUID()
    var name: String = ""
    var icon: String = "🗂️"
    var createdAt: Date = Date.now
    var sortIndex: Int = 0
    /// Template identifier ("budget", "todo", or "" for user-created).
    /// Lets AI/quick-add find well-known databases even if the user renames them.
    var templateKey: String = ""

    // MARK: Notion sync (per-database link)

    /// ID of the linked Notion database, if any.
    var notionDatabaseID: String?
    /// Cached title of the linked Notion database (for display only).
    var notionDatabaseTitle: String?
    /// Whether two-way sync is enabled for this database.
    var notionSyncEnabled: Bool = false
    /// When the last successful sync run finished.
    var notionLastSyncAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \POSProperty.database)
    var properties: [POSProperty]? = []

    @Relationship(deleteRule: .cascade, inverse: \POSEntry.database)
    var entries: [POSEntry]? = []

    init(name: String, icon: String = "🗂️", sortIndex: Int = 0, templateKey: String = "") {
        self.uuid = UUID()
        self.name = name
        self.icon = icon
        self.createdAt = .now
        self.sortIndex = sortIndex
        self.templateKey = templateKey
    }

    /// Properties in display order.
    var orderedProperties: [POSProperty] {
        (properties ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    var entryCount: Int { entries?.count ?? 0 }
}

// MARK: - Property (column definition)

@Model
final class POSProperty {
    var uuid: UUID = UUID()
    var name: String = ""
    var typeRaw: String = PropertyType.text.rawValue
    var sortIndex: Int = 0
    var configData: Data = Data()

    var database: POSDatabase?

    @Relationship(deleteRule: .cascade, inverse: \POSValue.property)
    var values: [POSValue]? = []

    init(name: String, type: PropertyType, sortIndex: Int = 0, config: PropertyConfig = .empty) {
        self.uuid = UUID()
        self.name = name
        self.typeRaw = type.rawValue
        self.sortIndex = sortIndex
        self.configData = config.encode()
    }

    var type: PropertyType {
        get { PropertyType(rawValue: typeRaw) ?? .text }
        set { typeRaw = newValue.rawValue }
    }

    var config: PropertyConfig {
        get { PropertyConfig.decode(configData) }
        set { configData = newValue.encode() }
    }
}

// MARK: - Entry (row)

@Model
final class POSEntry {
    var uuid: UUID = UUID()
    /// Every entry has a built-in title, like Notion's title column.
    var title: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // MARK: Import provenance
    //
    // Filled in when the entry was created by the mail importer rather than
    // by hand. `sourceMessageID` is the RFC 5322 Message-ID of the email and
    // is the primary dedupe key across devices.

    /// "" for hand-made entries, "email" for imported ones.
    var sourceKind: String = ""
    /// Message-ID of the email this entry came from.
    var sourceMessageID: String?
    /// Which parser rule produced it, e.g. "chase.card".
    var sourceRule: String?

    // MARK: Notion sync (per-entry state)

    /// Linked Notion page ID (nil = not yet pushed).
    var notionPageID: String?
    /// Local timestamp of the last successful push/pull of THIS entry.
    /// Push is needed iff `updatedAt > notionSyncedAt`.
    var notionSyncedAt: Date?
    /// The page's remote `last_edited_time` recorded at last sync.
    /// Pull is needed iff remote `last_edited_time > notionLastEditedAt`.
    /// Together these two fields prevent echo loops.
    var notionLastEditedAt: Date?

    var database: POSDatabase?

    @Relationship(deleteRule: .cascade, inverse: \POSValue.entry)
    var values: [POSValue]? = []

    init(title: String = "") {
        self.uuid = UUID()
        self.title = title
        self.createdAt = .now
        self.updatedAt = .now
    }
}

// MARK: - Value (cell)

@Model
final class POSValue {
    var uuid: UUID = UUID()
    var textValue: String?
    var numberValue: Double?
    var dateValue: Date?
    var boolValue: Bool?

    var entry: POSEntry?
    var property: POSProperty?

    init() {
        self.uuid = UUID()
    }

    var isEmpty: Bool {
        textValue == nil && numberValue == nil && dateValue == nil && boolValue == nil
    }
}

// MARK: - Balance anchor

/// A "the account really held this much at this moment" snapshot.
///
/// The app can't read the bank balance, so the user types it once and every
/// transaction dated after `recordedAt` is applied on top. Typing a fresh
/// anchor whenever the number drifts re-syncs it — old anchors are kept so
/// the history stays auditable.
@Model
final class POSBalanceAnchor {
    var uuid: UUID = UUID()
    var amount: Double = 0
    var recordedAt: Date = Date.now
    /// "manual" today; leaves room for a bank-email source later.
    var source: String = "manual"
    var note: String = ""

    init(amount: Double, recordedAt: Date = .now, source: String = "manual", note: String = "") {
        self.uuid = UUID()
        self.amount = amount
        self.recordedAt = recordedAt
        self.source = source
        self.note = note
    }
}

// MARK: - Merchant rule (learned category mapping)

/// User-taught mapping "if the raw merchant string contains X, file it under Y".
/// Checked before the built-in keyword table, newest first.
@Model
final class POSMerchantRule {
    var uuid: UUID = UUID()
    /// Uppercased substring matched against the raw merchant description.
    var pattern: String = ""
    /// Category name written into the 카테고리 property.
    var category: String = ""
    /// Optional prettier title to use instead of the cleaned merchant string.
    var displayName: String = ""
    var createdAt: Date = Date.now

    init(pattern: String, category: String, displayName: String = "") {
        self.uuid = UUID()
        self.pattern = pattern.uppercased()
        self.category = category
        self.displayName = displayName
        self.createdAt = .now
    }
}
