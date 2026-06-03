import Foundation
import SwiftData
import WidgetKit

final class WidgetDataWriter {
    static func write(_ snapshot: WidgetSnapshot) {
        guard
            let defaults = UserDefaults(suiteName: AppGroup.id),
            let data = try? JSONEncoder().encode(snapshot)
        else { return }
        defaults.set(data, forKey: AppGroup.widgetSnapshotKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func read() -> WidgetSnapshot {
        guard
            let defaults = UserDefaults(suiteName: AppGroup.id),
            let data = defaults.data(forKey: AppGroup.widgetSnapshotKey),
            let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    static func refresh(context: ModelContext, defaultCurrency: String = UserDefaults.standard.string(forKey: "defaultCurrency") ?? Currency.krw.rawValue) {
        let cal = Calendar.current
        let incompleteTasks = (try? context.fetch(
            FetchDescriptor<TodoItem>(predicate: #Predicate { !$0.isCompleted })
        )) ?? []
        let todayTasks = incompleteTasks.filter { $0.isDueToday || $0.isOverdue }
        let allEntries = (try? context.fetch(FetchDescriptor<BudgetEntry>())) ?? []
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: .now)) ?? .now
        let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) ?? .distantFuture
        let todaySpend = allEntries.filter {
            $0.isExpense && cal.isDateInToday($0.date) && $0.currency == defaultCurrency
        }.reduce(0) { $0 + $1.amount }
        let monthSpend = allEntries.filter {
            $0.isExpense && $0.date >= monthStart && $0.date < monthEnd && $0.currency == defaultCurrency
        }.reduce(0) { $0 + $1.amount }

        let snapshot = WidgetSnapshot(
            todayTaskCount: todayTasks.count,
            overdueCount: incompleteTasks.filter { $0.isOverdue }.count,
            todayTasks: todayTasks.prefix(3).map {
                WidgetSnapshot.WidgetTask(
                    title: $0.title,
                    isCompleted: $0.isCompleted,
                    dueDateString: $0.dueDate?.formatted(.dateTime.hour().minute())
                )
            },
            todaySpend: todaySpend,
            monthSpend: monthSpend,
            updatedAt: .now
        )
        write(snapshot)
    }
}
