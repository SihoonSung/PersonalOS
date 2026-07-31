import Foundation

// MARK: - Template semantics
//
// The budget/todo views need to know WHICH property plays which role.
// Resolution is name-first, then type-based fallback, so the views keep
// working even if the user renames or rebuilds properties.

extension POSDatabase {

    /// 금액 — named "금액" if present, else the first number property.
    var amountProperty: POSProperty? {
        orderedProperties.first { $0.name == "금액" && $0.type == .number }
            ?? orderedProperties.first { $0.type == .number }
    }

    /// The first date property (거래일 / 마감).
    var dateProperty: POSProperty? {
        orderedProperties.first { $0.type == .date }
    }

    /// 카테고리 — named match first, else the first select property.
    var categoryProperty: POSProperty? {
        orderedProperties.first { $0.name == "카테고리" && $0.type == .select }
            ?? orderedProperties.first { $0.type == .select }
    }

    /// 완료 — the first checkbox property.
    var doneProperty: POSProperty? {
        orderedProperties.first { $0.type == .checkbox }
    }

    /// 우선순위 — named select only (falling back to any select would
    /// collide with 카테고리-style properties).
    var priorityProperty: POSProperty? {
        orderedProperties.first { $0.name == "우선순위" && $0.type == .select }
    }

    /// Formats a raw amount using the 금액 property's number format.
    func formattedAmount(_ value: Double) -> String {
        guard let property = amountProperty else {
            return value.formatted(.number.precision(.fractionLength(0...2)))
        }
        let config = property.config
        if config.numberFormat == .currency {
            return value.formatted(.currency(code: config.currencyCode).precision(.fractionLength(0...2)))
        }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
