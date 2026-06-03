import SwiftUI
import SwiftData

struct TaskSummaryCard: View {
    @Query(filter: #Predicate<TodoItem> { !$0.isCompleted })
    private var incompleteTasks: [TodoItem]

    var todayCount: Int {
        incompleteTasks.filter { $0.isDueToday }.count
    }

    var overdueCount: Int {
        incompleteTasks.filter { $0.isOverdue && !$0.isDueToday }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            Label(L.taskSummaryLabel, systemImage: "checkmark.circle.fill")
                .font(Theme.caption().bold())
                .foregroundStyle(.secondary)

            HStack(spacing: Theme.spacingL) {
                StatPill(value: todayCount, label: L.taskToday, color: .blue)
                if overdueCount > 0 {
                    StatPill(value: overdueCount, label: L.taskOverdue, color: .red)
                }
                Spacer()
                Text(L.taskRemaining(incompleteTasks.count))
                    .font(Theme.caption())
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }
}

private struct StatPill: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.title2.bold())
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(Theme.caption2())
                .foregroundStyle(.secondary)
        }
    }
}
