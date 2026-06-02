import SwiftUI

struct AmountText: View {
    let amount: Double
    let isExpense: Bool
    var font: Font = Theme.body()

    var body: some View {
        Text(amount.formattedKRW())
            .font(font)
            .foregroundStyle(isExpense ? Theme.expenseRed : Theme.incomeGreen)
            .monospacedDigit()
    }
}

struct PnLText: View {
    let value: Double
    let percent: Double
    var font: Font = Theme.body()

    var isPositive: Bool { value >= 0 }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(isPositive ? "+" : "")\(value.formattedKRW())")
                .font(font)
                .foregroundStyle(isPositive ? Theme.positiveGreen : Theme.negativeRed)
                .monospacedDigit()
            Text("\(isPositive ? "+" : "")\(String(format: "%.2f", percent))%")
                .font(Theme.caption())
                .foregroundStyle(isPositive ? Theme.positiveGreen : Theme.negativeRed)
                .monospacedDigit()
        }
    }
}
