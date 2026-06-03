import SwiftUI
import SwiftData

struct BudgetSummaryCard: View {
    @Query private var allEntries: [BudgetEntry]
    @AppStorage("defaultCurrency") private var defaultCurrency: String = Currency.krw.rawValue
    @AppStorage("monthlyBudget") private var monthlyBudget: Double = 0

    private var primaryCurrency: Currency { Currency(rawValue: defaultCurrency) ?? .krw }

    private var currentMonthStart: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now
    }

    private var currentMonthEntries: [BudgetEntry] {
        let cal = Calendar.current
        guard
            let start = cal.date(from: cal.dateComponents([.year, .month], from: .now)),
            let end = cal.date(byAdding: .month, value: 1, to: start)
        else { return [] }
        return allEntries.filter { $0.date >= start && $0.date < end }
    }

    private var monthExpense: Double {
        currentMonthEntries.filter { $0.isExpense && $0.currency == defaultCurrency }.reduce(0) { $0 + $1.amount }
    }

    private var monthIncome: Double {
        currentMonthEntries.filter { !$0.isExpense && $0.currency == defaultCurrency }.reduce(0) { $0 + $1.amount }
    }

    private var carryover: Double {
        allEntries
            .filter { $0.currency == defaultCurrency && $0.date < currentMonthStart }
            .reduce(0) { partial, entry in
                partial + (entry.isExpense ? -entry.amount : entry.amount)
            }
    }

    private var totalBalance: Double {
        carryover + monthIncome - monthExpense
    }

    private var todayExpense: Double {
        allEntries.filter {
            $0.isExpense && $0.currency == defaultCurrency && Calendar.current.isDateInToday($0.date)
        }.reduce(0) { $0 + $1.amount }
    }

    private var hasOtherCurrency: Bool {
        currentMonthEntries.contains { $0.currency != defaultCurrency }
    }

    private var budgetProgress: Double {
        guard monthlyBudget > 0 else { return 0 }
        return min(monthExpense / monthlyBudget, 1.0)
    }

    private var isOverBudget: Bool { monthlyBudget > 0 && monthExpense > monthlyBudget }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            Label(L.budgetMonthlyTitle, systemImage: "creditcard.fill")
                .font(Theme.caption().bold())
                .foregroundStyle(.secondary)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(balanceText(totalBalance))
                        .font(.title2.bold())
                        .foregroundStyle(totalBalance >= 0 ? Theme.incomeGreen : Theme.expenseRed)
                        .monospacedDigit()
                    Text(L.budgetTotalBalance)
                        .font(Theme.caption2())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(primaryCurrency.format(monthIncome))
                        .font(Theme.headline())
                        .foregroundStyle(Theme.incomeGreen)
                        .monospacedDigit()
                    Text(L.budgetIncome)
                        .font(Theme.caption2())
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("\(L.budgetCarryover) \(balanceText(carryover))")
                    .font(Theme.caption2())
                    .foregroundStyle(carryover >= 0 ? .secondary : Theme.expenseRed)
                Spacer()
                Text("\(L.budgetExpense) \(primaryCurrency.format(monthExpense))")
                    .font(Theme.caption2())
                    .foregroundStyle(.secondary)
            }

            // 예산 진행바
            if monthlyBudget > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isOverBudget ? Color.orange : Color.blue)
                                .frame(width: geo.size.width * budgetProgress, height: 6)
                                .animation(.spring(duration: 0.5), value: budgetProgress)
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        if isOverBudget {
                            Label(
                                L.budgetOverBy(primaryCurrency.format(monthExpense - monthlyBudget)),
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(Theme.caption2().bold())
                            .foregroundStyle(.orange)
                        } else {
                            Text(L.budgetProgressPct(Int(budgetProgress * 100)))
                                .font(Theme.caption2())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("/ \(primaryCurrency.format(monthlyBudget))")
                            .font(Theme.caption2())
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            if hasOtherCurrency {
                Text(L.budgetOtherCurrency)
                    .font(Theme.caption2())
                    .foregroundStyle(.secondary)
            }

            if todayExpense > 0 {
                Divider()
                HStack {
                    Text(L.budgetTodayExpense)
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(primaryCurrency.format(todayExpense))
                        .font(Theme.caption().bold())
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
            }
        }
        .cardStyle()
    }

    private func balanceText(_ amount: Double) -> String {
        amount >= 0 ? primaryCurrency.format(amount) : "-\(primaryCurrency.format(abs(amount)))"
    }
}
