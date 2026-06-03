import SwiftUI
import SwiftData

struct TaskDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(CalendarService.self) private var calendarService
    @Bindable var task: TodoItem

    @Query(filter: #Predicate<Goal> { !$0.isCompleted }, sort: \Goal.createdAt)
    private var activeGoals: [Goal]

    var body: some View {
        NavigationStack {
            Form {
                Section(L.taskDetailSection) {
                    TextField(L.taskDetailTitle, text: $task.title)
                    TextField(L.taskDetailNotes, text: $task.notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section(L.taskDetailDueSection) {
                    Toggle(L.taskDetailDueToggle, isOn: Binding(
                        get: { task.dueDate != nil },
                        set: { if $0 { task.dueDate = Date.now } else { task.dueDate = nil } }
                    ))
                    if task.dueDate != nil {
                        DatePicker(L.taskDetailDuePicker, selection: Binding(
                            get: { task.dueDate ?? .now },
                            set: { task.dueDate = $0 }
                        ), displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                    }
                }

                Section(L.taskDetailPrioritySection) {
                    Picker(L.addTaskPriority, selection: $task.priority) {
                        Text(L.priorityNone).tag(0)
                        Text(L.priorityLow).tag(1)
                        Text(L.priorityMedium).tag(2)
                        Text(L.priorityHigh).tag(3)
                    }
                    .pickerStyle(.segmented)
                }

                Section(L.taskDetailRepeatSection) {
                    Picker(L.repeatNone, selection: Binding(
                        get: { task.repeatRule ?? "" },
                        set: { task.repeatRule = $0.isEmpty ? nil : $0 }
                    )) {
                        Text(L.repeatNone).tag("")
                        Text(L.repeatDaily).tag("FREQ=DAILY")
                        Text(L.repeatWeekly).tag("FREQ=WEEKLY")
                        Text(L.repeatMonthly).tag("FREQ=MONTHLY")
                    }
                    .pickerStyle(.menu)
                }

                if !activeGoals.isEmpty {
                    Section(L.taskGoalLink) {
                        Picker(L.taskGoalLink, selection: Binding(
                            get: { task.goalID },
                            set: { task.goalID = $0 }
                        )) {
                            Text(L.taskGoalNone).tag(nil as UUID?)
                            ForEach(activeGoals) { goal in
                                Label(goal.title, systemImage: goal.goalCategory.icon)
                                    .tag(goal.id as UUID?)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }

                if task.isCompleted, let completedAt = task.completedAt {
                    Section {
                        Label(
                            L.taskDetailCompleted(completedAt.formatted(.dateTime.month().day().hour().minute())),
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle(L.taskDetailNavTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear {
                commitChanges()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.taskDetailDone) {
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }

    private func commitChanges() {
        syncCalendar()
        try? context.save()
        WidgetDataWriter.refresh(context: context)
    }

    private func syncCalendar() {
        guard task.dueDate != nil else {
            // 마감일 없어졌으면 캘린더 이벤트 삭제
            if let id = task.calendarEventIdentifier {
                calendarService.removeEvent(identifier: id)
                task.calendarEventIdentifier = nil
            }
            return
        }
        if let id = task.calendarEventIdentifier {
            calendarService.updateEvent(identifier: id, for: task)
        } else {
            task.calendarEventIdentifier = calendarService.addEvent(for: task)
        }
    }
}
