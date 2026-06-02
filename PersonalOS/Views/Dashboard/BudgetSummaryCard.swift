import SwiftUI
import SwiftData

struct BudgetSummaryCard: View {
    @Query private var allEntries: [BudgetEntry]

    private var currentMonthEntries: [BudgetEntry] {
        let cal = Calendar.current
        let now = Date.now
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        return allEntries.filter { $0.date >= start }
    }

    private var monthExpense: Double {
        currentMonthEntries.filter { $0.isExpense }.reduce(0) { $0 + $1.amount }
    }

    private var monthIncome: Double {
        currentMonthEntries.filter { !$0.isExpense }.reduce(0) { $0 + $1.amount }
    }

    private var todayExpense: Double {
        allEntries
            .filter { $0.isExpense && Calendar.current.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            Label("이번 달 가계부", systemImage: "wonsign.circle.fill")
                .font(Theme.caption().bold())
                .foregroundStyle(.secondary)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(monthExpense.formattedKRW())
                        .font(.title2.bold())
                        .foregroundStyle(Theme.expenseRed)
                        .monospacedDigit()
                    Text("지출")
                        .font(Theme.caption2())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(monthIncome.formattedKRW())
                        .font(Theme.headline())
                        .foregroundStyle(Theme.incomeGreen)
                        .monospacedDigit()
                    Text("수입")
                        .font(Theme.caption2())
                        .foregroundStyle(.secondary)
                }
            }

            // 오늘 지출이 있으면 표시
            if todayExpense > 0 {
                Divider()
                HStack {
                    Text("오늘 지출")
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(todayExpense.formattedKRW())
                        .font(Theme.caption().bold())
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
            }
        }
        .cardStyle()
    }
}
