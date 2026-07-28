import SwiftUI
import SwiftData

/// 오늘 할 일 중심 메인 카드 — 진행률 + 체크 가능한 오늘/연체 목록
struct TodayFocusCard: View {
    @Environment(\.modelContext) private var context
    @Environment(CalendarService.self) private var calendarService

    @Query(
        filter: #Predicate<TodoItem> { !$0.isCompleted },
        sort: \TodoItem.dueDate
    )
    private var incompleteTasks: [TodoItem]

    @Query(filter: #Predicate<TodoItem> { $0.isCompleted })
    private var completedTasks: [TodoItem]

    private var focusTasks: [TodoItem] {
        incompleteTasks.filter { $0.isOverdue || $0.isDueToday }
    }

    private var doneTodayCount: Int {
        completedTasks.filter {
            guard let d = $0.completedAt else { return false }
            return Calendar.current.isDateInToday(d)
        }.count
    }

    private var totalCount: Int { focusTasks.count + doneTodayCount }

    private var progress: Double {
        totalCount == 0 ? 0 : Double(doneTodayCount) / Double(totalCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            HStack {
                Text(L.dashTodayTitle)
                    .font(Theme.caption().bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if totalCount > 0 {
                    Text(L.dashDoneCount(doneTodayCount, totalCount))
                        .font(Theme.caption().bold())
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }

            if focusTasks.isEmpty {
                HStack(spacing: Theme.spacingS) {
                    Image(systemName: totalCount == 0 ? "moon.zzz.fill" : "checkmark.seal.fill")
                        .foregroundStyle(.secondary)
                    Text(totalCount == 0 ? L.dashNoTasks : L.dashAllClear)
                        .font(Theme.body())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, Theme.spacingS)
            } else {
                progressBar
                    .padding(.bottom, Theme.spacingXS)

                ForEach(focusTasks.prefix(4)) { task in
                    taskRow(task)
                }

                if focusTasks.count > 4 {
                    Text(L.dashMoreTasks(focusTasks.count - 4))
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)
                        .padding(.leading, 30)
                }
            }
        }
        .glassCardStyle()
        .animation(.spring(duration: 0.35), value: focusTasks.count)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.glassTrack)
                Capsule()
                    .fill(Theme.glassInk.opacity(0.75))
                    .frame(width: max(geo.size.width * progress, progress > 0 ? 6 : 0))
            }
        }
        .frame(height: 5)
        .animation(.spring(duration: 0.4), value: progress)
    }

    private func taskRow(_ task: TodoItem) -> some View {
        HStack(spacing: Theme.spacingS) {
            Button {
                withAnimation(.spring(duration: 0.35)) {
                    TodoLifecycleService.setCompleted(
                        task,
                        completed: true,
                        context: context,
                        calendarService: calendarService
                    )
                }
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            PriorityDot(priority: task.priority)

            Text(task.title)
                .font(Theme.body())
                .lineLimit(1)

            Spacer()

            if task.isOverdue {
                Text(L.overdueBadge)
                    .font(Theme.caption2().bold())
                    .foregroundStyle(.red)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Color.red.opacity(0.12), in: Capsule())
            } else if let due = task.dueDate {
                Text(due.formatted(.dateTime.hour().minute()))
                    .font(Theme.caption())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }
}
