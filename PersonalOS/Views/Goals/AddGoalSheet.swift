import SwiftUI
import SwiftData

struct AddGoalSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var editing: Goal? = nil

    @State private var title = ""
    @State private var category = GoalCategory.other.rawValue
    @State private var targetText = ""
    @State private var currentText = ""
    @State private var unit = ""
    @State private var notes = ""
    @State private var hasDeadline = false
    @State private var deadline: Date = .now
    @State private var isCompleted = false

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        (targetText.sanitizedDouble ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L.addGoalTitlePlaceholder, text: $title)

                    Picker(L.addGoalCategory, selection: $category) {
                        ForEach(GoalCategory.allCases, id: \.rawValue) { cat in
                            Label(cat.localizedName, systemImage: cat.icon).tag(cat.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    HStack {
                        Text(L.addGoalTarget)
                        Spacer()
                        TextField("100", text: $targetText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    HStack {
                        Text(L.addGoalCurrent)
                        Spacer()
                        TextField("0", text: $currentText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    TextField(L.addGoalUnit, text: $unit)
                        .font(Theme.body())
                }

                Section {
                    Toggle(L.addGoalDeadlineToggle, isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker(L.addGoalDeadline, selection: $deadline, displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }
                    TextField(L.addGoalNotes, text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                if editing != nil {
                    Section {
                        Toggle(L.tasksSwipeComplete, isOn: $isCompleted)
                    }
                }
            }
            .navigationTitle(editing == nil ? L.addGoalNavTitle : L.editGoalNavTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { loadEditing() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L.addGoalCancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.addGoalSave) { save() }
                        .bold()
                        .disabled(!isValid)
                }
            }
        }
    }

    private func loadEditing() {
        guard let e = editing else { return }
        title = e.title
        category = e.goalCategory.rawValue
        targetText = formatValue(e.targetValue)
        currentText = formatValue(e.currentValue)
        unit = e.unit
        notes = e.notes
        isCompleted = e.isCompleted
        if let d = e.deadline {
            hasDeadline = true
            deadline = d
        }
    }

    private func formatValue(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }

    private func save() {
        let target = targetText.sanitizedDouble ?? 0
        guard target > 0 else { return }

        let current = currentText.sanitizedDouble ?? 0

        if let e = editing {
            e.title = title.trimmingCharacters(in: .whitespaces)
            e.category = category
            e.targetValue = target
            e.currentValue = min(current, target)
            e.unit = unit.trimmingCharacters(in: .whitespaces)
            e.notes = notes.trimmingCharacters(in: .whitespaces)
            e.deadline = hasDeadline ? deadline : nil
            e.isCompleted = isCompleted
        } else {
            context.insert(Goal(
                title: title.trimmingCharacters(in: .whitespaces),
                targetValue: target,
                currentValue: min(current, target),
                unit: unit.trimmingCharacters(in: .whitespaces),
                deadline: hasDeadline ? deadline : nil,
                category: category,
                notes: notes.trimmingCharacters(in: .whitespaces)
            ))
        }
        try? context.save()
        dismiss()
    }
}
