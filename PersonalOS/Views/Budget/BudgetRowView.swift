import SwiftUI

struct BudgetRowView: View {
    let entry: BudgetEntry

    var body: some View {
        HStack(spacing: Theme.spacingM) {
            // 카테고리 아이콘
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: entry.budgetCategory.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(categoryColor)
            }

            // 내용
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.merchant.isEmpty ? entry.budgetCategory.localizedName : entry.merchant)
                    .font(Theme.body())
                    .lineLimit(1)

                HStack(spacing: Theme.spacingS) {
                    Text(entry.budgetCategory.localizedName)
                        .font(Theme.caption2())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())

                    if !entry.note.isEmpty {
                        Text(entry.note)
                            .font(Theme.caption2())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // 금액
            AmountText(amount: entry.amount, currency: entry.currency, isExpense: entry.isExpense, font: Theme.body())
        }
        .padding(.vertical, Theme.spacingXS)
    }

    private var categoryColor: Color {
        switch entry.budgetCategory {
        case .food: return .orange
        case .coffee: return .brown
        case .transport: return .blue
        case .shopping: return .pink
        case .entertainment: return .purple
        case .health: return .red
        case .subscription: return .indigo
        case .utility: return .yellow
        case .salary: return .green
        case .investmentIncome: return .teal
        case .other: return .gray
        }
    }
}
