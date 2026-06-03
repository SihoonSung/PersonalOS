import SwiftUI
import SwiftData

struct BudgetDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var entry: BudgetEntry

    @State private var amountText: String = ""

    // @Bindable 편집은 모델에 즉시 반영되므로, 취소를 위해 원본 값을 보관한다.
    @State private var original: Snapshot?

    private struct Snapshot {
        let type: String
        let merchant: String
        let amount: Double
        let currency: String
        let category: String
        let date: Date
        let note: String
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L.budgetDetailType) {
                    Picker(L.budgetDetailType, selection: $entry.type) {
                        Text(L.addBudgetExpense).tag("expense")
                        Text(L.addBudgetIncome).tag("income")
                    }
                    .pickerStyle(.segmented)
                }

                Section(L.budgetDetailContent) {
                    TextField(L.budgetDetailMerchant, text: $entry.merchant)
                    HStack {
                        Text(L.budgetDetailAmount)
                        Spacer()
                        TextField(L.budgetDetailAmount, text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: amountText) { _, v in
                                entry.amount = v.sanitizedDouble ?? entry.amount
                            }
                        Picker("", selection: $entry.currency) {
                            ForEach(Currency.allCases, id: \.rawValue) { c in
                                Text(c.symbol).tag(c.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }

                Section(L.budgetDetailCategory) {
                    Picker(L.budgetDetailCategory, selection: $entry.category) {
                        ForEach(BudgetCategory.allCases, id: \.rawValue) { cat in
                            Label(cat.localizedName, systemImage: cat.icon).tag(cat.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section(L.budgetDetailDateMemo) {
                    DatePicker(L.budgetDetailDate, selection: $entry.date, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    TextField(L.budgetDetailNote, text: $entry.note)
                }
            }
            .navigationTitle(L.budgetDetailNavTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // 정규화 이전의 원본 값을 한 번만 보관 (취소 복원용)
                if original == nil {
                    original = Snapshot(
                        type: entry.type,
                        merchant: entry.merchant,
                        amount: entry.amount,
                        currency: entry.currency,
                        category: entry.category,
                        date: entry.date,
                        note: entry.note
                    )
                }
                entry.category = entry.budgetCategory.rawValue
                entry.currency = Currency(rawValue: entry.currency.uppercased())?.rawValue ?? Currency.krw.rawValue
                let cur = Currency(rawValue: entry.currency) ?? .krw
                switch cur {
                case .krw: amountText = String(Int(entry.amount))
                case .usd: amountText = String(format: "%.2f", entry.amount)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L.addBudgetCancel) {
                        restoreOriginal()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.budgetDetailDone) {
                        try? context.save()
                        WidgetDataWriter.refresh(context: context)
                        BudgetAlertService.check(context: context)
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }

    private func restoreOriginal() {
        guard let o = original else { return }
        entry.type = o.type
        entry.merchant = o.merchant
        entry.amount = o.amount
        entry.currency = o.currency
        entry.category = o.category
        entry.date = o.date
        entry.note = o.note
        try? context.save()
    }
}
