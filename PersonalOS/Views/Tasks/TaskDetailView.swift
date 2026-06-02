import SwiftUI

struct TaskDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var task: TodoItem

    var body: some View {
        NavigationStack {
            Form {
                Section("할 일") {
                    TextField("제목", text: $task.title)
                    TextField("메모 (선택)", text: $task.notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("마감일") {
                    Toggle("마감일 설정", isOn: Binding(
                        get: { task.dueDate != nil },
                        set: { if $0 { task.dueDate = Date.now } else { task.dueDate = nil } }
                    ))

                    if let _ = task.dueDate {
                        DatePicker("마감일", selection: Binding(
                            get: { task.dueDate ?? .now },
                            set: { task.dueDate = $0 }
                        ), displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                    }
                }

                Section("우선순위") {
                    Picker("우선순위", selection: $task.priority) {
                        Text("없음").tag(0)
                        Text("낮음").tag(1)
                        Text("보통").tag(2)
                        Text("높음").tag(3)
                    }
                    .pickerStyle(.segmented)
                }

                Section("반복") {
                    Picker("반복", selection: Binding(
                        get: { task.repeatRule ?? "" },
                        set: { task.repeatRule = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("없음").tag("")
                        Text("매일").tag("FREQ=DAILY")
                        Text("매주").tag("FREQ=WEEKLY")
                        Text("매월").tag("FREQ=MONTHLY")
                    }
                    .pickerStyle(.menu)
                }

                if task.isCompleted, let completedAt = task.completedAt {
                    Section {
                        Label(
                            "완료: \(completedAt.formatted(.dateTime.month().day().hour().minute()))",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("할 일 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") {
                        try? context.save()
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}
