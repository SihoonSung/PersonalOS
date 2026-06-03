import SwiftUI
import SwiftData

struct TaskRowView: View {
    @Environment(\.modelContext) private var context
    @Environment(CalendarService.self) private var calendarService
    let task: TodoItem

    var body: some View {
        HStack(spacing: Theme.spacingM) {
            // 완료 버튼
            Button {
                toggleComplete()
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            // 내용
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    PriorityDot(priority: task.priority)
                    Text(task.title)
                        .font(Theme.body())
                        .strikethrough(task.isCompleted, color: .secondary)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                        .lineLimit(2)
                }

                HStack(spacing: Theme.spacingS) {
                    if let dueDate = task.dueDate {
                        dueDateChip(dueDate)
                    }
                    if let rule = task.repeatRule, !rule.isEmpty {
                        Label(L.tasksRepeat, systemImage: "repeat")
                            .font(Theme.caption2())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, Theme.spacingXS)
        .opacity(task.isCompleted ? 0.5 : 1.0)
    }

    @ViewBuilder
    private func dueDateChip(_ date: Date) -> some View {
        if task.isOverdue && !task.isCompleted {
            Label(
                date.formatted(.dateTime.month(.abbreviated).day().hour().minute()),
                systemImage: "exclamationmark.circle.fill"
            )
            .font(Theme.caption2().bold())
            .foregroundStyle(.red)
        } else if task.isDueToday {
            Label(
                date.formatted(.dateTime.hour().minute()),
                systemImage: "clock"
            )
            .font(Theme.caption2())
            .foregroundStyle(.orange)
        } else {
            Label(
                date.formatted(.dateTime.month(.abbreviated).day()),
                systemImage: "calendar"
            )
            .font(Theme.caption2())
            .foregroundStyle(.secondary)
        }
    }

    private func toggleComplete() {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()

        withAnimation(.spring(duration: 0.3)) {
            TodoLifecycleService.setCompleted(
                task,
                completed: !task.isCompleted,
                context: context,
                calendarService: calendarService
            )
        }
    }
}
