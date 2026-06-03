import SwiftUI
import SwiftData

struct AddInvestmentSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var editing: Investment? = nil

    @State private var ticker = ""
    @State private var name = ""
    @State private var sharesText = ""
    @State private var avgCostText = ""
    @State private var currency = "USD"

    private var isValid: Bool {
        !ticker.trimmingCharacters(in: .whitespaces).isEmpty &&
        (sharesText.sanitizedDouble ?? 0) > 0 &&
        (avgCostText.sanitizedDouble ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L.addInvestmentTicker, text: $ticker)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField(L.addInvestmentName, text: $name)
                } header: {
                    Text(L.addInvestmentTicker)
                }

                Section {
                    HStack {
                        Text(L.addInvestmentShares)
                        Spacer()
                        TextField("0", text: $sharesText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }
                    HStack {
                        Text(L.addInvestmentAvgCost)
                        Spacer()
                        TextField("0", text: $avgCostText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                        Picker("", selection: $currency) {
                            ForEach(Currency.allCases, id: \.rawValue) { c in
                                Text(c.symbol).tag(c.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                } header: {
                    Text(L.addInvestmentShares)
                }
            }
            .navigationTitle(editing == nil ? L.addInvestmentNavTitle : L.editInvestmentNavTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { loadEditing() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L.addInvestmentCancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.addInvestmentSave) { save() }
                        .bold()
                        .disabled(!isValid)
                }
            }
        }
    }

    private func loadEditing() {
        guard let e = editing else { return }
        ticker = e.ticker
        name = e.name
        sharesText = String(format: "%g", e.shares)
        avgCostText = e.currency == "USD"
            ? String(format: "%.2f", e.averageCost)
            : String(Int(e.averageCost))
        currency = e.currency
    }

    private func save() {
        let shares = sharesText.sanitizedDouble ?? 0
        let avgCost = avgCostText.sanitizedDouble ?? 0
        guard shares > 0, avgCost > 0 else { return }

        let tickerUpper = ticker.trimmingCharacters(in: .whitespaces).uppercased()

        if let e = editing {
            e.ticker = tickerUpper
            e.name = name.trimmingCharacters(in: .whitespaces)
            e.shares = shares
            e.averageCost = avgCost
            e.currency = currency
        } else {
            context.insert(Investment(
                ticker: tickerUpper,
                name: name.trimmingCharacters(in: .whitespaces),
                shares: shares,
                averageCost: avgCost,
                currency: currency
            ))
        }
        try? context.save()
        dismiss()
    }
}
