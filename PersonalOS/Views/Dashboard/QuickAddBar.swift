import SwiftUI
import SwiftData

struct QuickAddBar: View {
    @Environment(\.modelContext) private var context
    @Environment(AIAvailabilityManager.self) private var aiAvailability

    @State private var inputText = ""
    @State private var isExpanded = false
    @State private var isParsing = false

    // 파싱 결과
    @State private var parsedTodo: ParsedTodoInput?
    @State private var parsedBudget: ParsedBudgetInput?
    @State private var detectedType: InputType = .unknown

    // 저장 완료 피드백
    @State private var savedMessage: String?

    private let parsingService = AIParsingService()

    enum InputType { case todo, budget, unknown }

    var body: some View {
        VStack(spacing: 0) {
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
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                    .font(.system(size: 16))

                TextField("할 일이나 지출을 입력해 보세요...", text: $inputText)
                    .font(Theme.body())
                    .onSubmit { Task { await save() } }
                    .onChange(of: inputText) { _, newValue in
                        debounceParseInput(newValue)
                    }

                if !inputText.isEmpty {
                    if isParsing || parsedTodo != nil || parsedBudget != nil {
                        Button("저장") { Task { await save() } }
                            .font(Theme.body().bold())
                            .foregroundStyle(.blue)
                    }
                    Button {
                        inputText = ""
                        parsedTodo = nil
                        parsedBudget = nil
                        detectedType = .unknown
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(Theme.spacingM)
            .background(Theme.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusL))
            .padding(.horizontal, Theme.spacingM)
        }
        .animation(.spring(duration: 0.3), value: isParsing)
        .animation(.spring(duration: 0.3), value: parsedTodo?.title)
        .animation(.spring(duration: 0.3), value: parsedBudget?.merchant)
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

        // 간단한 휴리스틱: 숫자+원/달러 포함 → 가계부, 그 외 → 할 일
        let budgetKeywords = ["원", "달러", "$", "₩", "만원", "천원", "월급", "급여"]
        let looksLikeBudget = budgetKeywords.contains { text.contains($0) }

        do {
            if looksLikeBudget {
                let result = try await parsingService.parseBudget(input: text)
                if !Task.isCancelled {
                    parsedBudget = result
                    parsedTodo = nil
                    detectedType = .budget
                }
            } else {
                let result = try await parsingService.parseTodo(input: text)
                if !Task.isCancelled {
                    parsedTodo = result
                    parsedBudget = nil
                    detectedType = .todo
                }
            }
        } catch {
            // AI 실패 시 조용히 무시 — 수동 저장 가능
        }

        isParsing = false
    }

    // MARK: - 저장

    @MainActor
    private func save() async {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()

        if let todo = parsedTodo {
            saveTodo(from: todo, raw: text)
            savedMessage = "'\(todo.title)' 추가됨"
        } else if let budget = parsedBudget {
            saveBudget(from: budget, raw: text)
            savedMessage = "\(budget.merchant) \(budget.amount.formattedKRW()) 기록됨"
        } else {
            // AI 파싱 없이 기본 할 일로 저장
            let item = TodoItem(title: text, rawInput: text)
            context.insert(item)
            savedMessage = "'\(text)' 추가됨"
        }

        try? context.save()
        inputText = ""
        parsedTodo = nil
        parsedBudget = nil
        detectedType = .unknown

        // 저장 메시지 1.5초 후 사라짐
        withAnimation { }
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
        }
    }

    private func saveBudget(from parsed: ParsedBudgetInput, raw: String) {
        let entry = BudgetEntry(
            amount: parsed.amount,
            type: parsed.type,
            merchant: parsed.merchant,
            category: parsed.category,
            note: parsed.note ?? "",
            date: parseISODate(parsed.dateISO) ?? .now,
            rawInput: raw
        )
        context.insert(entry)
    }
}
