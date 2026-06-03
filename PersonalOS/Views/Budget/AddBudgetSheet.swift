import SwiftUI
import SwiftData

struct AddBudgetSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AIAvailabilityManager.self) private var aiAvailability
    @AppStorage("defaultCurrency") private var defaultCurrency: String = Currency.krw.rawValue

    @State private var inputText = ""
    @State private var isParsing = false
    @State private var parsedResult: ParsedBudgetInput?

    // 수동 입력
    @State private var manualMerchant = ""
    @State private var manualAmount: Double = 0
    @State private var manualAmountText = ""
    @State private var manualType = "expense"
    @State private var manualCategory = BudgetCategory.other.rawValue
    @State private var manualCurrency = "KRW"
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

                    Text(L.addBudgetNLTitle)
                        .font(Theme.caption().bold())
                        .foregroundStyle(.secondary)

                    TextEditor(text: $inputText)
                        .font(Theme.body())
                        .frame(minHeight: 70, maxHeight: 100)
                        .padding(Theme.spacingS)
                        .background(Theme.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusS))

                    Text(L.addBudgetNLExample)
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)

                    if aiAvailability.isAvailable && !inputText.isEmpty {
                        Button {
                            Task { await parseInput() }
                        } label: {
                            Label(isParsing ? L.addBudgetAIParsing : L.addBudgetAIAnalyze, systemImage: "sparkles")
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
                        Text(L.addBudgetParsedTitle)
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
                        Picker(L.addBudgetType, selection: $manualType) {
                            Text(L.addBudgetExpense).tag("expense")
                            Text(L.addBudgetIncome).tag("income")
                        }
                        .pickerStyle(.segmented)
                    }

                    Section(L.addBudgetContentSection) {
                        TextField(L.addBudgetMerchant, text: $manualMerchant)
                        HStack {
                            Text(L.addBudgetAmount)
                            Spacer()
                            TextField(L.addBudgetAmountZero, text: $manualAmountText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: manualAmountText) { _, v in
                                    manualAmount = v.sanitizedDouble ?? 0
                                }
                            Picker("", selection: $manualCurrency) {
                                ForEach(Currency.allCases, id: \.rawValue) { c in
                                    Text(c.symbol).tag(c.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                    }

                    Section(L.addBudgetCategory) {
                        Picker(L.addBudgetCategory, selection: $manualCategory) {
                            ForEach(BudgetCategory.allCases, id: \.rawValue) { cat in
                                Label(cat.localizedName, systemImage: cat.icon).tag(cat.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Section(L.addBudgetDateMemo) {
                        DatePicker(L.addBudgetDate, selection: $manualDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                        TextField(L.addBudgetNote, text: $manualNote)
                    }
                }
                .onAppear { manualCurrency = defaultCurrency }
            }
            .navigationTitle(L.addBudgetNavTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L.addBudgetCancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.addBudgetSave) { saveEntry() }
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

        let dateContext = ParsingDateContext.current()
        let result = await withAIFallback(fallback: nil as ParsedBudgetInput?) {
            try await parsingService.parseBudget(
                input: inputText,
                defaultCurrency: defaultCurrency,
                dateContext: dateContext
            )
        }
        parsedResult = result
        if let result {
            applyParsedResult(result)
        }
        isParsing = false
    }

    private func applyParsedResult(_ p: ParsedBudgetInput) {
        manualMerchant = p.merchant
        manualAmount = p.amount
        let normalizedCurrency = Currency(rawValue: p.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())?.rawValue ?? defaultCurrency
        let parsedCur = Currency(rawValue: normalizedCurrency) ?? .krw
        manualAmountText = parsedCur == .usd ? String(format: "%.2f", p.amount) : String(Int(p.amount))
        manualType = p.type == "income" ? "income" : "expense"
        manualCategory = BudgetCategory.from(p.category).rawValue
        manualCurrency = normalizedCurrency
        manualDate = parseISODate(p.dateISO) ?? .now
        manualNote = p.note ?? ""
    }

    private func saveEntry() {
        guard manualAmount > 0 else { return }

        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()

        let entry = BudgetEntry(
            amount: manualAmount,
            currency: Currency(rawValue: manualCurrency) ?? .krw,
            type: manualType == "income" ? .income : .expense,
            merchant: manualMerchant.trimmingCharacters(in: .whitespaces),
            category: BudgetCategory.from(manualCategory),
            note: manualNote.trimmingCharacters(in: .whitespaces),
            date: manualDate,
            rawInput: inputText.isEmpty ? nil : inputText
        )
        context.insert(entry)
        try? context.save()
        WidgetDataWriter.refresh(context: context, defaultCurrency: defaultCurrency)
        BudgetAlertService.check(context: context)
        dismiss()
    }
}
