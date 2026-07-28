import SwiftUI
import SwiftData

/// 대시보드용 컴팩트 예산 글래스 카드
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

    private var budgetProgress: Double {
        guard monthlyBudget > 0 else { return 0 }
        return min(monthExpense / monthlyBudget, 1.0)
    }

    private var isOverBudget: Bool { monthlyBudget > 0 && monthExpense > monthlyBudget }

    private var mainAmount: Double {
        monthlyBudget > 0 ? monthlyBudget - monthExpense : totalBalance
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            Text(L.dashBudgetTitle)
                .font(Theme.caption().bold())
                .foregroundStyle(.secondary)

            Text(balanceText(mainAmount))
                .font(.title3.bold())
                .foregroundStyle(mainAmount >= 0 ? Color.primary : Theme.expenseRed)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if monthlyBudget > 0 {
                if isOverBudget {
                    Label(
                        L.dashBudgetOver(primaryCurrency.format(monthExpense - monthlyBudget)),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(Theme.caption2().bold())
                    .foregroundStyle(.orange)
                } else {
                    Text(L.dashBudgetUsed(Int(budgetProgress * 100)))
                        .font(Theme.caption2())
                        .foregroundStyle(.secondary)
                }

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.glassTrack)
                    GeometryReader { geo in
                        Capsule()
                            .fill(isOverBudget ? AnyShapeStyle(Color.orange) : AnyShapeStyle(Theme.glassInk.opacity(0.75)))
                            .frame(width: geo.size.width * budgetProgress)
                            .animation(.spring(duration: 0.5), value: budgetProgress)
                    }
                }
                .frame(height: 5)
            } else {
                Text(L.budgetTotalBalance)
                    .font(Theme.caption2())
                    .foregroundStyle(.secondary)
            }

            if todayExpense > 0 {
                Text("\(L.dashTodaySpent) \(primaryCurrency.format(todayExpense))")
                    .font(Theme.caption2())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle()
    }

    private func balanceText(_ amount: Double) -> String {
        amount >= 0 ? primaryCurrency.format(amount) : "-\(primaryCurrency.format(abs(amount)))"
    }
}
