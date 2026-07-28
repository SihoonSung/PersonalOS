import SwiftUI
import SwiftData

struct QuickAddBar: View {
    @Environment(\.modelContext) private var context
    @Environment(AIAvailabilityManager.self) private var aiAvailability
    @Environment(CalendarService.self) private var calendarService
    @AppStorage("defaultCurrency") private var defaultCurrency: String = Currency.krw.rawValue

    @State private var inputText = ""
    @State private var isParsing = false

    // 파싱 결과
    @State private var parsedTodo: ParsedTodoInput?
    @State private var parsedBudget: ParsedBudgetInput?
    @State private var detectedType: InputType = .unknown

    // AI 꺼진 상태에서 수동 타입 선택
    @State private var manualType: InputType = .todo

    // 저장 완료 피드백
    @State private var savedMessage: String?

    private let parsingService = AIParsingService()

    enum InputType: String, CaseIterable {
        case todo, budget, unknown

        var label: String {
            switch self {
            case .todo:    return L.quickAddTypeTodo
            case .budget:  return L.quickAddTypeBudget
            case .unknown: return ""
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // AI 꺼진 상태 — 타입 선택 세그먼트
            if !aiAvailability.isAvailable && !inputText.isEmpty {
                Picker(L.quickAddTypeLabel, selection: $manualType) {
                    Text(L.quickAddTypeTodo).tag(InputType.todo)
                    Text(L.quickAddTypeBudget).tag(InputType.budget)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.spacingM)
                .padding(.bottom, Theme.spacingS)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // 파싱 미리보기
            if isParsing {
                ShimmerChips()
                    .padding(.bottom, Theme.spacingS)
            } else if let todo = parsedTodo {
                TodoPreviewChips(parsed: todo)
                    .padding(.bottom, Theme.spacingS)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let budget = parsedBudget {
                BudgetPreviewChips(parsed: budget)
                    .padding(.bottom, Theme.spacingS)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // 입력창
            HStack(spacing: Theme.spacingS) {
                Image(systemName: aiAvailability.isAvailable ? "sparkles" : "pencil")
                    .foregroundStyle(aiAvailability.isAvailable ? .blue : .secondary)
                    .font(.system(size: 16))

                TextField(placeholderText, text: $inputText)
                    .font(Theme.body())
                    .onSubmit { Task { await save() } }
                    .onChange(of: inputText) { _, newValue in
                        debounceParseInput(newValue)
                    }

                if !inputText.isEmpty {
                    if isParsing || parsedTodo != nil || parsedBudget != nil || !aiAvailability.isAvailable {
                        Button(L.quickAddSave) { Task { await save() } }
                            .font(Theme.body().bold())
                            .foregroundStyle(.blue)
                    }
                    Button {
                        inputText = ""
                        parsedTodo = nil
                        parsedBudget = nil
                        detectedType = .unknown
                        debounceTask?.cancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, Theme.spacingM)
            .padding(.vertical, 14)
            .glassEffect(.regular.interactive(), in: .capsule)
            .padding(.horizontal, Theme.spacingM)
        }
        .animation(.spring(duration: 0.3), value: isParsing)
        .animation(.spring(duration: 0.3), value: parsedTodo?.title)
        .animation(.spring(duration: 0.3), value: parsedBudget?.merchant)
        .animation(.spring(duration: 0.3), value: inputText.isEmpty)
        .overlay(alignment: .top) {
            if let msg = savedMessage {
                Text(msg)
                    .font(Theme.caption().bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.spacingM)
                    .padding(.vertical, Theme.spacingS)
                    .background(Color.green)
                    .clipShape(Capsule())
                    .offset(y: -40)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var placeholderText: String {
        if aiAvailability.isAvailable { return L.quickAddPlaceholderAI }
        return manualType == .budget ? L.quickAddPlaceholderBudget : L.quickAddPlaceholderTodo
    }

    // MARK: - AI 파싱 (400ms 디바운스)

    @State private var debounceTask: Task<Void, Never>?

    private func debounceParseInput(_ text: String) {
        debounceTask?.cancel()
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            parsedTodo = nil
            parsedBudget = nil
            detectedType = .unknown
            return
        }
        parsedTodo = nil
        parsedBudget = nil
        detectedType = .unknown
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await parseInput(text)
        }
    }

    @MainActor
    private func parseInput(_ text: String) async {
        guard aiAvailability.isAvailable else { return }
        isParsing = true
        defer { isParsing = false }

        do {
            let dateContext = ParsingDateContext.current()
            let classification = try await parsingService.classifyInput(input: text)
            let type = normalizedType(from: classification.type) ?? keywordFallbackType(for: text)
            try await parse(text, as: type, dateContext: dateContext)
        } catch {
            try? await parse(text, as: keywordFallbackType(for: text), dateContext: .current())
        }
    }

    private func normalizedType(from rawType: String) -> InputType? {
        switch rawType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "todo", "task", "reminder":
            return .todo
        case "budget", "expense", "income", "transaction":
            return .budget
        default:
            return nil
        }
    }

    private func keywordFallbackType(for text: String) -> InputType {
        let budgetKeywords = ["원", "달러", "$", "₩", "만원", "천원", "월급", "급여"]
        return budgetKeywords.contains { text.contains($0) } ? .budget : .todo
    }

    @MainActor
    private func parse(_ text: String, as type: InputType, dateContext: ParsingDateContext) async throws {
        switch type {
        case .budget:
            let result = try await parsingService.parseBudget(
                input: text,
                defaultCurrency: defaultCurrency,
                dateContext: dateContext
            )
            guard !Task.isCancelled, inputText == text else { return }
            parsedBudget = result
            parsedTodo = nil
            detectedType = .budget
        case .todo, .unknown:
            let result = try await parsingService.parseTodo(input: text, dateContext: dateContext)
            guard !Task.isCancelled, inputText == text else { return }
            parsedTodo = result
            parsedBudget = nil
            detectedType = .todo
        }
    }

    // MARK: - 저장

    @MainActor
    private func save() async {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        debounceTask?.cancel()

        // 파싱이 끝나기 전에 저장을 누른 경우(레이스) → 먼저 파싱을 완료시킨다.
        // 이게 없으면 "버스 2000원" 같은 가계부 입력이 할 일로 잘못 저장될 수 있음.
        if aiAvailability.isAvailable, parsedTodo == nil, parsedBudget == nil {
            await parseInput(text)
        }
        isParsing = false

        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()

        if let todo = parsedTodo {
            saveTodo(from: todo, raw: text)
            savedMessage = L.quickAddSavedTodo(todo.title)
        } else if let budget = parsedBudget {
            saveBudget(from: budget, raw: text)
            let currencyCode = budget.currency.isEmpty ? defaultCurrency : budget.currency.uppercased()
            let cur = Currency(rawValue: currencyCode) ?? .krw
            savedMessage = L.quickAddSavedBudget(budget.merchant, cur.format(budget.amount))
        } else {
            // AI 미지원이거나 파싱 실패 → 로컬 폴백.
            // AI 꺼짐: 사용자가 고른 세그먼트(manualType) / AI 켜짐인데 실패: 키워드로 추론.
            let type: InputType = aiAvailability.isAvailable ? keywordFallbackType(for: text) : manualType
            if type == .budget {
                let parsed = AmountParser.parse(text, defaultCurrency: defaultCurrency)
                let entry = BudgetEntry(
                    amount: parsed.amount,
                    currency: Currency(rawValue: parsed.currency) ?? .krw,
                    type: .expense,
                    merchant: text,
                    rawInput: text
                )
                context.insert(entry)
                let cur = Currency(rawValue: parsed.currency) ?? .krw
                savedMessage = L.quickAddSavedBudget(text, cur.format(parsed.amount))
            } else {
                let item = TodoItem(title: text, rawInput: text)
                context.insert(item)
                savedMessage = L.quickAddSavedTodo(text)
            }
        }

        try? context.save()
        WidgetDataWriter.refresh(context: context, defaultCurrency: defaultCurrency)
        BudgetAlertService.check(context: context)
        inputText = ""
        parsedTodo = nil
        parsedBudget = nil
        detectedType = .unknown

        try? await Task.sleep(for: .milliseconds(1500))
        withAnimation { savedMessage = nil }
    }

    private func saveTodo(from parsed: ParsedTodoInput, raw: String) {
        let item = TodoItem(
            title: parsed.title,
            notes: parsed.notes ?? "",
            priority: parsed.priority,
            dueDate: parseISODate(parsed.dueDateISO),
            repeatRule: parsed.repeatRule,
            rawInput: raw
        )
        context.insert(item)
        if item.dueDate != nil {
            Task { await NotificationService.requestPermission() }
            NotificationService.scheduleTodoReminder(for: item)
            if let identifier = calendarService.addEvent(for: item) {
                item.calendarEventIdentifier = identifier
            }
        }
    }

    private func saveBudget(from parsed: ParsedBudgetInput, raw: String) {
        let currency = Currency(rawValue: parsed.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()) ?? Currency(rawValue: defaultCurrency) ?? .krw
        let entry = BudgetEntry(
            amount: parsed.amount,
            currency: currency,
            type: parsed.type == "income" ? .income : .expense,
            merchant: parsed.merchant,
            category: BudgetCategory.from(parsed.category),
            note: parsed.note ?? "",
            date: parseISODate(parsed.dateISO) ?? .now,
            rawInput: raw
        )
        context.insert(entry)
    }

}
