import SwiftData
import Foundation

// 월급, 넷플릭스 등 반복 수입/지출 템플릿
@Model
final class RecurringEntry {
    var id: UUID
    var title: String          // "넷플릭스", "월급"
    var amount: Double
    var currency: String       // "KRW" | "USD"
    var type: String           // "expense" | "income"
    var category: String       // BudgetCategory.rawValue
    var note: String
    var dayOfMonth: Int        // 매월 몇 일 (1~31)
    var isActive: Bool
    var createdAt: Date
    var lastAppliedMonth: String  // "2025-07" 형식 — 중복 생성 방지

    init(
        id: UUID = UUID(),
        title: String,
        amount: Double,
        currency: Currency = .krw,
        type: EntryType = .expense,
        category: BudgetCategory = .subscription,
        note: String = "",
        dayOfMonth: Int = 1,
        isActive: Bool = true,
        createdAt: Date = .now,
        lastAppliedMonth: String = ""
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.currency = currency.rawValue
        self.type = type.rawValue
        self.category = category.rawValue
        self.note = note
        self.dayOfMonth = dayOfMonth
        self.isActive = isActive
        self.createdAt = createdAt
        self.lastAppliedMonth = lastAppliedMonth
    }

    var isExpense: Bool { type == "expense" }

    var budgetCategory: BudgetCategory {
        BudgetCategory.from(category)
    }

    var currencyEnum: Currency {
        Currency(rawValue: currency) ?? .krw
    }
}
