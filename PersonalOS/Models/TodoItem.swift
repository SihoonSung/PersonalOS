import SwiftData
import Foundation

@Model
final class TodoItem {
    var id: UUID
    var title: String
    var notes: String
    var priority: Int
    var dueDate: Date?
    var isCompleted: Bool
    var completedAt: Date?
    var repeatRule: String?
    var createdAt: Date
    var rawInput: String?
    var goalID: UUID?
    var calendarEventIdentifier: String? = nil  // EKEvent.eventIdentifier — 캘린더 연동 시 저장

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
        goalID: UUID? = nil,
        calendarEventIdentifier: String? = nil
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
        self.calendarEventIdentifier = calendarEventIdentifier
    }

    var isOverdue: Bool {
        guard let d = dueDate, !isCompleted else { return false }
        return d < Date.now
    }

    var isDueToday: Bool {
        guard let d = dueDate else { return false }
        return Calendar.current.isDateInToday(d)
    }

    var priorityEnum: Priority { Priority(rawValue: priority) ?? .none }
    var priorityLabel: String { priorityEnum.label }
    var priorityColor: String { priorityEnum.color }
}
