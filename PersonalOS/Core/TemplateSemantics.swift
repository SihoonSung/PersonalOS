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

    /// 유형 (지출/수입/이체) — named select only, for the same reason.
    var kindProperty: POSProperty? {
        orderedProperties.first { $0.name == "유형" && $0.type == .select }
    }

    /// 확인됨 — the review flag written by the mail importer.
    var reviewedProperty: POSProperty? {
        orderedProperties.first { $0.name == "확인됨" && $0.type == .checkbox }
    }

    /// 결제수단.
    var methodProperty: POSProperty? {
        orderedProperties.first { $0.name == "결제수단" }
    }

    /// 메모 — 사람이 직접 적는 한 줄. 스크린샷 기록에서 "왜 보냈는지"가 들어간다.
    var memoProperty: POSProperty? {
        orderedProperties.first { $0.name == "메모" && $0.type == .text }
    }

    /// 출처 이메일 — raw merchant / sender string kept for auditing.
    var sourceProperty: POSProperty? {
        orderedProperties.first { $0.name == "출처 이메일" }
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

extension POSEntry {

    /// 유형 — defaults to 지출 when the property is missing or unset, which
    /// keeps pre-migration rows and hand-typed rows behaving as before.
    func kind(in database: POSDatabase) -> String {
        guard let property = database.kindProperty,
              let raw = text(for: property), !raw.isEmpty
        else { return EntryKind.expense }
        return raw
    }

    /// Only 지출 rows count toward month totals, budgets and category charts.
    func countsAsSpending(in database: POSDatabase) -> Bool {
        EntryKind.countsAsSpending(kind(in: database))
    }

    /// 급여처럼 실제로 번 돈만 수입 통계에 넣는다. 정산금은 빠진다.
    func countsAsIncome(in database: POSDatabase) -> Bool {
        EntryKind.countsAsIncome(kind(in: database))
    }

    /// 잔액에 더할 값 — 들어온 돈은 +, 나간 돈은 −.
    func balanceDelta(in database: POSDatabase) -> Double {
        let amount = database.amountProperty.flatMap { number(for: $0) } ?? 0
        return EntryKind.sign(kind(in: database)) * abs(amount)
    }

    /// 거래 시각 — 날짜 속성이 비어 있으면 생성 시각으로 대체.
    func effectiveDate(in database: POSDatabase) -> Date {
        database.dateProperty.flatMap { date(for: $0) } ?? createdAt
    }
}
