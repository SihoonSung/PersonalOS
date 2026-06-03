import SwiftData
import Foundation

@Model
final class BudgetEntry {
    var id: UUID
    var amount: Double
    var currency: String = "KRW"       // Currency.rawValue
    var type: String                   // EntryType.rawValue
    var merchant: String
    var category: String               // BudgetCategory.rawValue
    var note: String
    var date: Date
    var createdAt: Date
    var rawInput: String?

    init(
        id: UUID = UUID(),
        amount: Double,
        currency: Currency = .krw,
        type: EntryType = .expense,
        merchant: String = "",
        category: BudgetCategory = .other,
        note: String = "",
        date: Date = .now,
        createdAt: Date = .now,
        rawInput: String? = nil
    ) {
        self.id = id
        self.amount = amount
        self.currency = currency.rawValue
        self.type = type.rawValue
        self.merchant = merchant
        self.category = category.rawValue
        self.note = note
        self.date = date
        self.createdAt = createdAt
        self.rawInput = rawInput
    }

    var isExpense: Bool { type == EntryType.expense.rawValue }

    var entryType: EntryType { EntryType(rawValue: type) ?? .expense }
    var currencyEnum: Currency { Currency(rawValue: currency) ?? .krw }

    var budgetCategory: BudgetCategory {
        BudgetCategory.from(category)
    }
}
