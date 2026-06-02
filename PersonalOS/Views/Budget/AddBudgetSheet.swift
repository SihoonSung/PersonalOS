import SwiftUI
import SwiftData

struct AddBudgetSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AIAvailabilityManager.self) private var aiAvailability

    @State private var inputText = ""
    @State private var isParsing = false
    @State private var parsedResult: ParsedBudgetInput?

    // 수동 입력
    @State private var manualMerchant = ""
    @State private var manualAmount: Double = 0
    @State private var manualAmountText = ""
    @State private var manualType = "expense"
    @State private var manualCategory = BudgetCategory.other.rawValue
    @State private var manualDate: Date = .now
    @State private var manualNote = ""

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
                        .frame(minHeight: 70, maxHeight: 100)
                        .padding(Theme.spacingS)
                        .background(Theme.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusS))

                    Text("예시: \"스타벅스 6000원\", \"어제 택시 12000원\", \"월급 280만원\"")
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)

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
                    ShimmerChips().padding(.bottom, Theme.spacingS)
                } else if let parsed = parsedResult {
                    VStack(alignment: .leading, spacing: Theme.spacingS) {
                        Text("파싱 결과")
                            .font(Theme.caption().bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Theme.spacingM)
                        BudgetPreviewChips(parsed: parsed)
                    }
                    .padding(.bottom, Theme.spacingS)
                }

                Divider()

                Form {
                    // 수입/지출 토글
                    Section {
                        Picker("유형", selection: $manualType) {
                            Text("지출").tag("expense")
                            Text("수입").tag("income")
                        }
                        .pickerStyle(.segmented)
                    }

                    Section("내용") {
                        TextField("상호명 / 내용", text: $manualMerchant)
                        HStack {
                            Text("금액")
                            Spacer()
                            TextField("0", text: $manualAmountText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: manualAmountText) { _, v in
                                    manualAmount = Double(v.filter { $0.isNumber }) ?? 0
                                }
                            Text("원")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("카테고리") {
                        Picker("카테고리", selection: $manualCategory) {
                            ForEach(BudgetCategory.allCases, id: \.rawValue) { cat in
                                Label(cat.rawValue, systemImage: cat.icon).tag(cat.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Section("날짜 / 메모") {
                        DatePicker("날짜", selection: $manualDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                        TextField("메모 (선택)", text: $manualNote)
                    }
                }
                .onChange(of: parsedResult) { _, parsed in
                    if let p = parsed {
                        manualMerchant = p.merchant
                        manualAmount = p.amount
                        manualAmountText = String(Int(p.amount))
                        manualType = p.type
                        manualCategory = p.category
                        if let date = parseISODate(p.dateISO) {
                            manualDate = date
                        }
                        manualNote = p.note ?? ""
                    }
                }
            }
            .navigationTitle("지출/수입 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("저장") { saveEntry() }
                        .bold()
                        .disabled(manualAmount <= 0)
                }
            }
        }
    }

    private func parseInput() async {
        guard !inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isParsing = true
        parsedResult = nil

        let result = await withAIFallback(fallback: nil as ParsedBudgetInput?) {
            try await parsingService.parseBudget(input: inputText)
        }
        parsedResult = result
        isParsing = false
    }

    private func saveEntry() {
        guard manualAmount > 0 else { return }

        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()

        let entry = BudgetEntry(
            amount: manualAmount,
            type: manualType,
            merchant: manualMerchant.trimmingCharacters(in: .whitespaces),
            category: manualCategory,
            note: manualNote.trimmingCharacters(in: .whitespaces),
            date: manualDate,
            rawInput: inputText.isEmpty ? nil : inputText
        )
        context.insert(entry)
        try? context.save()
        dismiss()
    }
}
