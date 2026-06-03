import SwiftUI

struct AmountText: View {
    let amount: Double
    var currency: String = "KRW"
    let isExpense: Bool
    var font: Font = Theme.body()

    var body: some View {
        let cur = Currency(rawValue: currency) ?? .krw
        Text(cur.format(amount))
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
            Text("\(isPositive ? "+" : "")\(Currency.usd.format(value))")
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
