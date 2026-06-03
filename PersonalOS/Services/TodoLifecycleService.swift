import Foundation
import SwiftData

enum TodoLifecycleService {
    @MainActor
    static func setCompleted(
        _ task: TodoItem,
        completed: Bool,
        context: ModelContext,
        calendarService: CalendarService
    ) {
        task.isCompleted = completed
        task.completedAt = completed ? .now : nil

        if completed {
            NotificationService.cancelTodoReminder(todoID: task.id)
            if let id = task.calendarEventIdentifier {
                calendarService.markEventCompleted(identifier: id)
            }
            // 연결된 목표가 있으면 진행도 +1
            incrementGoalIfLinked(task, context: context)
            // 반복 할 일이면 다음 회차를 새 할 일로 생성
            scheduleNextOccurrenceIfNeeded(from: task, context: context, calendarService: calendarService)
        } else if task.dueDate != nil {
            Task { await NotificationService.requestPermission() }
            NotificationService.scheduleTodoReminder(for: task)
            if let id = task.calendarEventIdentifier {
                calendarService.unmarkEventCompleted(identifier: id)
                calendarService.updateEvent(identifier: id, for: task)
            } else if let identifier = calendarService.addEvent(for: task) {
                task.calendarEventIdentifier = identifier
            }
        }

        try? context.save()
        WidgetDataWriter.refresh(context: context)
    }

    @MainActor
    static func delete(
        _ task: TodoItem,
        context: ModelContext,
        calendarService: CalendarService
    ) {
        NotificationService.cancelTodoReminder(todoID: task.id)
        if let id = task.calendarEventIdentifier {
            calendarService.removeEvent(identifier: id)
        }
        context.delete(task)
        try? context.save()
        WidgetDataWriter.refresh(context: context)
    }

    // MARK: - 목표 연동

    @MainActor
    private static func incrementGoalIfLinked(_ task: TodoItem, context: ModelContext) {
        guard let goalID = task.goalID else { return }
        let descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { $0.id == goalID && !$0.isCompleted }
        )
        guard let goal = try? context.fetch(descriptor).first else { return }
        goal.currentValue = min(goal.currentValue + 1, goal.targetValue)
        if goal.currentValue >= goal.targetValue {
            goal.isCompleted = true
        }
    }

    // MARK: - 반복 처리

    /// 완료된 반복 할 일의 다음 회차를 생성한다. 현재 항목의 반복 규칙은 다음 회차로 넘기고,
    /// 완료된 항목에서는 제거해 (재완료 시) 중복 생성을 막는다.
    @MainActor
    private static func scheduleNextOccurrenceIfNeeded(
        from task: TodoItem,
        context: ModelContext,
        calendarService: CalendarService
    ) {
        guard let rule = task.repeatRule, !rule.isEmpty,
              let due = task.dueDate,
              let next = nextOccurrence(after: due, rule: rule) else { return }

        let copy = TodoItem(
            title: task.title,
            notes: task.notes,
            priority: task.priority,
            dueDate: next,
            isCompleted: false,
            repeatRule: rule,
            goalID: task.goalID
        )
        context.insert(copy)

        // 완료된 회차는 더 이상 반복 소스가 아님
        task.repeatRule = nil

        Task { await NotificationService.requestPermission() }
        NotificationService.scheduleTodoReminder(for: copy)
        if let identifier = calendarService.addEvent(for: copy) {
            copy.calendarEventIdentifier = identifier
        }
    }

    /// FREQ=DAILY/WEEKLY/MONTHLY 규칙에 따라 다음 발생일을 계산.
    static func nextOccurrence(after date: Date, rule: String) -> Date? {
        let cal = Calendar.current
        let upper = rule.uppercased()
        if upper.contains("FREQ=DAILY") {
            return cal.date(byAdding: .day, value: 1, to: date)
        }
        if upper.contains("FREQ=WEEKLY") {
            return cal.date(byAdding: .weekOfYear, value: 1, to: date)
        }
        if upper.contains("FREQ=MONTHLY") {
            return cal.date(byAdding: .month, value: 1, to: date)
        }
        return nil
    }
}
