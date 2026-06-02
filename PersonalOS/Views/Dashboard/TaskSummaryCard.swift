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
            Label("할 일", systemImage: "checkmark.circle.fill")
                .font(Theme.caption().bold())
                .foregroundStyle(.secondary)

            HStack(spacing: Theme.spacingL) {
                StatPill(value: todayCount, label: "오늘", color: .blue)
                if overdueCount > 0 {
                    StatPill(value: overdueCount, label: "연체", color: .red)
                }
                Spacer()
                Text("\(incompleteTasks.count)개 남음")
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
