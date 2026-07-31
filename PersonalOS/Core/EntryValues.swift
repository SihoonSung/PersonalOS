import Foundation
import SwiftData

// MARK: - Typed cell access
//
// POSEntry ↔ POSValue plumbing so the rest of the app never touches
// raw optionals directly.

extension POSEntry {

    /// The stored cell for a property, if any.
    func value(for property: POSProperty) -> POSValue? {
        (values ?? []).first { $0.property?.uuid == property.uuid }
    }

    /// The stored cell, creating it (attached to the same context) if missing.
    func ensureValue(for property: POSProperty, context: ModelContext) -> POSValue {
        if let existing = value(for: property) { return existing }
        let v = POSValue()
        v.entry = self
        v.property = property
        context.insert(v)
        return v
    }

    func touch() { updatedAt = .now }

    // MARK: Typed getters

    func text(for property: POSProperty) -> String? {
        value(for: property)?.textValue
    }

    func number(for property: POSProperty) -> Double? {
        value(for: property)?.numberValue
    }

    func date(for property: POSProperty) -> Date? {
        value(for: property)?.dateValue
    }

    func bool(for property: POSProperty) -> Bool {
        value(for: property)?.boolValue ?? false
    }

    // MARK: Typed setters

    func setText(_ newValue: String?, for property: POSProperty, context: ModelContext) {
        let v = ensureValue(for: property, context: context)
        v.textValue = (newValue?.isEmpty == true) ? nil : newValue
        touch()
    }

    func setNumber(_ newValue: Double?, for property: POSProperty, context: ModelContext) {
        ensureValue(for: property, context: context).numberValue = newValue
        touch()
    }

    func setDate(_ newValue: Date?, for property: POSProperty, context: ModelContext) {
        ensureValue(for: property, context: context).dateValue = newValue
        touch()
    }

    func setBool(_ newValue: Bool, for property: POSProperty, context: ModelContext) {
        ensureValue(for: property, context: context).boolValue = newValue
        touch()
    }

    // MARK: Display

    /// Human-readable string for any cell — used by list rows, Mac table, exports, MCP.
    func displayString(for property: POSProperty) -> String {
        guard let v = value(for: property), !v.isEmpty else { return "" }
        switch property.type {
        case .text, .select, .url:
            return v.textValue ?? ""
        case .checkbox:
            return (v.boolValue ?? false) ? "✓" : ""
        case .number:
            guard let n = v.numberValue else { return "" }
            let config = property.config
            if config.numberFormat == .currency {
                return n.formatted(.currency(code: config.currencyCode).precision(.fractionLength(0...2)))
            }
            return n.formatted(.number.precision(.fractionLength(0...2)))
        case .date:
            guard let d = v.dateValue else { return "" }
            if property.config.includeTime {
                return d.formatted(date: .abbreviated, time: .shortened)
            }
            return d.formatted(date: .abbreviated, time: .omitted)
        }
    }

    /// JSON-friendly value for exports and the MCP server.
    func jsonValue(for property: POSProperty) -> Any? {
        guard let v = value(for: property), !v.isEmpty else { return nil }
        switch property.type {
        case .text, .select, .url:
            return v.textValue
        case .checkbox:
            return v.boolValue
        case .number:
            return v.numberValue
        case .date:
            guard let d = v.dateValue else { return nil }
            return ISO8601DateFormatter().string(from: d)
        }
    }
}
