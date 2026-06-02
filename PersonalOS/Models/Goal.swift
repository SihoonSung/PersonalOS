import SwiftData
import Foundation

@Model
final class Goal {
    var id: UUID
    var title: String
    var targetValue: Double
    var currentValue: Double
    var unit: String
    var deadline: Date?
    var category: String       // GoalCategory.rawValue
    var isCompleted: Bool
    var createdAt: Date
    var notes: String

    init(
        id: UUID = UUID(),
        title: String,
        targetValue: Double,
        currentValue: Double = 0,
        unit: String = "",
        deadline: Date? = nil,
        category: String = GoalCategory.other.rawValue,
        isCompleted: Bool = false,
        createdAt: Date = .now,
        notes: String = ""
    ) {
        self.id = id
        self.title = title
        self.targetValue = targetValue
        self.currentValue = currentValue
        self.unit = unit
        self.deadline = deadline
        self.category = category
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.notes = notes
    }

    var progress: Double {
        guard targetValue > 0 else { return 0 }
        return min(currentValue / targetValue, 1.0)
    }

    var progressPercent: Int { Int(progress * 100) }

    var goalCategory: GoalCategory {
        GoalCategory(rawValue: category) ?? .other
    }
}
