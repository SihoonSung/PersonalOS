import SwiftData
import Foundation

@Model
final class TodoItem {
    var id: UUID
    var title: String
    var notes: String
    var priority: Int          // 0=없음 1=낮음 2=보통 3=높음
    var dueDate: Date?
    var isCompleted: Bool
    var completedAt: Date?
    var repeatRule: String?    // RRULE: "FREQ=DAILY", "FREQ=WEEKLY;BYDAY=MO"
    var createdAt: Date
    var rawInput: String?
    var goalID: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        priority: Int = 0,
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        repeatRule: String? = nil,
        createdAt: Date = .now,
        rawInput: String? = nil,
        goalID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.priority = priority
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.repeatRule = repeatRule
        self.createdAt = createdAt
        self.rawInput = rawInput
        self.goalID = goalID
    }

    var isOverdue: Bool {
        guard let d = dueDate, !isCompleted else { return false }
        return d < Date.now
    }

    var isDueToday: Bool {
        guard let d = dueDate else { return false }
        return Calendar.current.isDateInToday(d)
    }

    var priorityLabel: String {
        switch priority {
        case 3: return "높음"
        case 2: return "보통"
        case 1: return "낮음"
        default: return ""
        }
    }

    var priorityColor: String {
        switch priority {
        case 3: return "red"
        case 2: return "orange"
        case 1: return "blue"
        default: return "gray"
        }
    }
}
