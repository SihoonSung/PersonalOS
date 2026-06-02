import SwiftData
import Foundation

@Model
final class BudgetEntry {
    var id: UUID
    var amount: Double
    var type: String           // "expense" | "income"
    var merchant: String
    var category: String       // BudgetCategory.rawValue
    var note: String
    var date: Date
    var createdAt: Date
    var rawInput: String?

    init(
        id: UUID = UUID(),
        amount: Double,
        type: String = "expense",
        merchant: String = "",
        category: String = BudgetCategory.other.rawValue,
        note: String = "",
        date: Date = .now,
        createdAt: Date = .now,
        rawInput: String? = nil
    ) {
        self.id = id
        self.amount = amount
        self.type = type
        self.merchant = merchant
        self.category = category
        self.note = note
        self.date = date
        self.createdAt = createdAt
        self.rawInput = rawInput
    }

    var isExpense: Bool { type == "expense" }

    var budgetCategory: BudgetCategory {
        BudgetCategory(rawValue: category) ?? .other
    }
}
