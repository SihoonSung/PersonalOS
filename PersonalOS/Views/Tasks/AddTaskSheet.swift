import SwiftUI
import SwiftData

struct AddTaskSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AIAvailabilityManager.self) private var aiAvailability

    @State private var inputText = ""
    @State private var isParsing = false
    @State private var parsedResult: ParsedTodoInput?

    // 수동 입력 폴백
    @State private var manualTitle = ""
    @State private var manualDueDate: Date = .now
    @State private var manualHasDueDate = false
    @State private var manualPriority = 0

    private let parsingService = AIParsingService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // AI 자연어 입력
                VStack(alignment: .leading, spacing: Theme.spacingS) {
                    if !aiAvailability.isAvailable {
                        AIUnavailableBanner(message: aiAvailability.unavailableReason)
                    }

                    Text("자연어로 입력")
                        .font(Theme.caption().bold())
                        .foregroundStyle(.secondary)

                    TextEditor(text: $inputText)
                        .font(Theme.body())
                        .frame(minHeight: 80, maxHeight: 120)
                        .padding(Theme.spacingS)
                        .background(Theme.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusS))

                    Text("예시: \"다음주 금요일까지 보고서 제출\", \"내일 오후 3시 병원 예약\"")
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)

                    // AI 파싱 버튼
                    if aiAvailability.isAvailable && !inputText.isEmpty {
                        Button {
                            Task { await parseInput() }
                        } label: {
                            Label(isParsing ? "분석 중..." : "AI로 분석", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isParsing)
                    }
                }
                .padding(Theme.spacingM)

                // 파싱 결과 미리보기
                if isParsing {
                    ShimmerChips()
                        .padding(.bottom, Theme.spacingS)
                } else if let parsed = parsedResult {
                    VStack(alignment: .leading, spacing: Theme.spacingS) {
                        Text("파싱 결과")
                            .font(Theme.caption().bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Theme.spacingM)
                        TodoPreviewChips(parsed: parsed)
                    }
                    .padding(.bottom, Theme.spacingS)
                }

                Divider()

                // 수동 입력 폼
                Form {
                    Section("직접 입력") {
                        TextField("할 일 제목", text: $manualTitle)
                        Toggle("마감일", isOn: $manualHasDueDate)
                        if manualHasDueDate {
                            DatePicker("날짜/시간", selection: $manualDueDate, displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.compact)
                        }
                        Picker("우선순위", selection: $manualPriority) {
                            Text("없음").tag(0)
                            Text("낮음").tag(1)
                            Text("보통").tag(2)
                            Text("높음").tag(3)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .onChange(of: parsedResult) { _, parsed in
                    // 파싱 결과를 수동 폼에도 반영
                    if let p = parsed {
                        manualTitle = p.title
                        manualPriority = p.priority
                        if let dateStr = p.dueDateISO, let date = parseISODate(dateStr) {
                            manualDueDate = date
                            manualHasDueDate = true
                        }
                    }
                }
            }
            .navigationTitle("할 일 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("저장") { saveTask() }
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

        let result = await withAIFallback(fallback: nil as ParsedTodoInput?) {
            try await parsingService.parseTodo(input: inputText)
        }
        parsedResult = result
        isParsing = false
    }

    private func saveTask() {
        let title = manualTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()

        let item = TodoItem(
            title: title,
            priority: manualPriority,
            dueDate: manualHasDueDate ? manualDueDate : nil,
            rawInput: inputText.isEmpty ? nil : inputText
        )
        context.insert(item)

        if item.dueDate != nil {
            Task { await NotificationService.requestPermission() }
            NotificationService.scheduleTodoReminder(for: item)
        }

        try? context.save()
        dismiss()
    }
}
