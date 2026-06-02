import SwiftUI
import SwiftData

struct TasksView: View {
    @Environment(\.modelContext) private var context

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
        case active = "미완료"
        case today = "오늘"
        case overdue = "연체"
        case completed = "완료"
    }

    private var filteredTasks: [TodoItem] {
        switch filter {
        case .active:
            return allTasks.filter { !$0.isCompleted }
        case .today:
            return allTasks.filter { !$0.isCompleted && ($0.isDueToday || $0.isOverdue) }
        case .overdue:
            return allTasks.filter { $0.isOverdue }
        case .completed:
            return allTasks.filter { $0.isCompleted }
                .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 필터 탭
                Picker("필터", selection: $filter) {
                    ForEach(TaskFilter.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
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
                                        Label("삭제", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        withAnimation {
                                            task.isCompleted.toggle()
                                            task.completedAt = task.isCompleted ? .now : nil
                                            try? context.save()
                                        }
                                    } label: {
                                        Label(
                                            task.isCompleted ? "미완료로" : "완료",
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
            .navigationTitle("할 일")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddTaskSheet()
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $selectedTask) { task in
                TaskDetailView(task: task)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.spacingM) {
            Spacer()
            Image(systemName: "checkmark.circle.dashed")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text(emptyMessage)
                .font(Theme.headline())
                .foregroundStyle(.primary)
            Text("자연어로 입력해 보세요\n예: \"내일 오후 3시 병원 예약\"")
                .font(Theme.body())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("할 일 추가") { showAddSheet = true }
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding(Theme.spacingXL)
    }

    private var emptyMessage: String {
        switch filter {
        case .active: return "할 일이 없어요"
        case .today: return "오늘 할 일이 없어요"
        case .overdue: return "연체된 할 일이 없어요"
        case .completed: return "완료된 할 일이 없어요"
        }
    }

    private func deleteTask(_ task: TodoItem) {
        NotificationService.cancelTodoReminder(todoID: task.id)
        context.delete(task)
        try? context.save()
    }
}
