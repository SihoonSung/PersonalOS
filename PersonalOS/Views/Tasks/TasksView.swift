import SwiftUI
import SwiftData

struct TasksView: View {
    @State private var mainTab: MainTab = .tasks

    enum MainTab { case tasks, goals }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $mainTab) {
                    Text(L.tabTasks).tag(MainTab.tasks)
                    Text(L.goalsSegment).tag(MainTab.goals)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.spacingM)
                .padding(.top, Theme.spacingS)

                switch mainTab {
                case .tasks:  TaskListView()
                case .goals:  GoalsView()
                }
            }
            .navigationTitle(mainTab == .tasks ? L.tasksNavTitle : L.goalsNavTitle)
        }
    }
}

// MARK: - 할 일 목록 (기존 TasksView 내용 분리)

private struct TaskListView: View {
    @Environment(\.modelContext) private var context
    @Environment(CalendarService.self) private var calendarService

    @Query(sort: [
        SortDescriptor(\TodoItem.dueDate, order: .forward),
        SortDescriptor(\TodoItem.priority, order: .reverse),
        SortDescriptor(\TodoItem.createdAt, order: .forward)
    ])
    private var allTasks: [TodoItem]

    @State private var showAddSheet = false
    @State private var selectedTask: TodoItem?
    @State private var filter: TaskFilter = .active

    enum TaskFilter: String, CaseIterable {
        case active, today, overdue, completed

        var label: String {
            switch self {
            case .active:    return L.tasksFilterActive
            case .today:     return L.tasksFilterToday
            case .overdue:   return L.tasksFilterOverdue
            case .completed: return L.tasksFilterDone
            }
        }
    }

    private var filteredTasks: [TodoItem] {
        switch filter {
        case .active:    return allTasks.filter { !$0.isCompleted }
        case .today:     return allTasks.filter { !$0.isCompleted && ($0.isDueToday || $0.isOverdue) }
        case .overdue:   return allTasks.filter { $0.isOverdue }
        case .completed: return allTasks.filter { $0.isCompleted }
                             .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(L.tasksFilterLabel, selection: $filter) {
                ForEach(TaskFilter.allCases, id: \.self) {
                    Text($0.label).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .padding(Theme.spacingM)

            if filteredTasks.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filteredTasks) { task in
                        TaskRowView(task: task)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedTask = task }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deleteTask(task)
                                } label: {
                                    Label(L.tasksSwipeDelete, systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    withAnimation {
                                        TodoLifecycleService.setCompleted(
                                            task,
                                            completed: !task.isCompleted,
                                            context: context,
                                            calendarService: calendarService
                                        )
                                    }
                                } label: {
                                    Label(
                                        task.isCompleted ? L.tasksSwipeUncomplete : L.tasksSwipeComplete,
                                        systemImage: task.isCompleted ? "arrow.uturn.left" : "checkmark"
                                    )
                                }
                                .tint(task.isCompleted ? .orange : .green)
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddTaskSheet().presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task).presentationDetents([.medium, .large])
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.spacingM) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text(L.tasksEmptyMessage(filter.label))
                .font(Theme.headline())
                .foregroundStyle(.primary)
            Text(L.tasksEmptyInstruction)
                .font(Theme.body())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L.tasksAddButton) { showAddSheet = true }
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding(Theme.spacingXL)
    }

    private func deleteTask(_ task: TodoItem) {
        TodoLifecycleService.delete(task, context: context, calendarService: calendarService)
    }
}
