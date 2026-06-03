import SwiftUI
import SwiftData

struct AddTaskSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AIAvailabilityManager.self) private var aiAvailability
    @Environment(CalendarService.self) private var calendarService

    @State private var inputText = ""
    @State private var isParsing = false
    @State private var parsedResult: ParsedTodoInput?

    @State private var manualTitle = ""
    @State private var manualDueDate: Date = .now
    @State private var manualHasDueDate = false
    @State private var manualPriority = 0
    @State private var selectedGoalID: UUID? = nil

    @Query(filter: #Predicate<Goal> { !$0.isCompleted }, sort: \Goal.createdAt)
    private var activeGoals: [Goal]

    private let parsingService = AIParsingService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: Theme.spacingS) {
                    if !aiAvailability.isAvailable {
                        AIUnavailableBanner(message: aiAvailability.unavailableReason)
                    }

                    Text(L.addTaskNLTitle)
                        .font(Theme.caption().bold())
                        .foregroundStyle(.secondary)

                    TextEditor(text: $inputText)
                        .font(Theme.body())
                        .frame(minHeight: 80, maxHeight: 120)
                        .padding(Theme.spacingS)
                        .background(Theme.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusS))

                    Text(L.addTaskNLExample)
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)

                    if aiAvailability.isAvailable && !inputText.isEmpty {
                        Button {
                            Task { await parseInput() }
                        } label: {
                            Label(isParsing ? L.addTaskAIParsing : L.addTaskAIAnalyze, systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isParsing)
                    }
                }
                .padding(Theme.spacingM)

                if isParsing {
                    ShimmerChips().padding(.bottom, Theme.spacingS)
                } else if let parsed = parsedResult {
                    VStack(alignment: .leading, spacing: Theme.spacingS) {
                        Text(L.addTaskParsedTitle)
                            .font(Theme.caption().bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Theme.spacingM)
                        TodoPreviewChips(parsed: parsed)
                    }
                    .padding(.bottom, Theme.spacingS)
                }

                Divider()

                Form {
                    Section(L.addTaskManualTitle) {
                        TextField(L.addTaskTitlePlaceholder, text: $manualTitle)
                        Toggle(L.addTaskDueDateToggle, isOn: $manualHasDueDate)
                        if manualHasDueDate {
                            DatePicker(L.addTaskDueDatePicker, selection: $manualDueDate, displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.compact)
                        }
                        Picker(L.addTaskPriority, selection: $manualPriority) {
                            Text(L.priorityNone).tag(0)
                            Text(L.priorityLow).tag(1)
                            Text(L.priorityMedium).tag(2)
                            Text(L.priorityHigh).tag(3)
                        }
                        .pickerStyle(.segmented)

                        if !activeGoals.isEmpty {
                            Picker(L.taskGoalLink, selection: $selectedGoalID) {
                                Text(L.taskGoalNone).tag(nil as UUID?)
                                ForEach(activeGoals) { goal in
                                    Label(goal.title, systemImage: goal.goalCategory.icon)
                                        .tag(goal.id as UUID?)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
            }
            .navigationTitle(L.addTaskNavTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L.addTaskCancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.addTaskSave) { saveTask() }
                        .bold()
                        .disabled(manualTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func parseInput() async {
        guard !inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isParsing = true
        parsedResult = nil
        let dateContext = ParsingDateContext.current()
        let result = await withAIFallback(fallback: nil as ParsedTodoInput?) {
            try await parsingService.parseTodo(input: inputText, dateContext: dateContext)
        }
        parsedResult = result
        if let result {
            applyParsedResult(result)
        }
        isParsing = false
    }

    private func applyParsedResult(_ p: ParsedTodoInput) {
        manualTitle = p.title
        manualPriority = min(max(p.priority, 0), 3)
        if let date = parseISODate(p.dueDateISO) {
            manualDueDate = date
            manualHasDueDate = true
        } else {
            manualDueDate = .now
            manualHasDueDate = false
        }
    }

    private func saveTask() {
        let title = manualTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()
        let item = TodoItem(
            title: title,
            notes: parsedResult?.notes ?? "",
            priority: manualPriority,
            dueDate: manualHasDueDate ? manualDueDate : nil,
            repeatRule: parsedResult?.repeatRule,
            rawInput: inputText.isEmpty ? nil : inputText,
            goalID: selectedGoalID
        )
        context.insert(item)
        if item.dueDate != nil {
            Task { await NotificationService.requestPermission() }
            NotificationService.scheduleTodoReminder(for: item)
            // 캘린더 연동
            if let identifier = calendarService.addEvent(for: item) {
                item.calendarEventIdentifier = identifier
            }
        }
        try? context.save()
        WidgetDataWriter.refresh(context: context)
        dismiss()
    }
}
