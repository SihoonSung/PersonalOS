import SwiftUI

// MARK: - TODO 파싱 결과 미리보기

struct TodoPreviewChips: View {
    let parsed: ParsedTodoInput
    var onEditTitle: () -> Void = {}

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.spacingS) {
                // 제목 칩
                PreviewChip(
                    icon: "checkmark.circle",
                    text: parsed.title,
                    color: .blue,
                    action: onEditTitle
                )

                // 날짜 칩
                if let dateStr = parsed.dueDateISO,
                   let date = parseISODate(dateStr) {
                    PreviewChip(
                        icon: "calendar",
                        text: date.formatted(.dateTime.month(.abbreviated).day().hour().minute()),
                        color: .orange
                    )
                }

                // 우선순위 칩
                if parsed.priority > 0 {
                    PreviewChip(
                        icon: "flag.fill",
                        text: priorityLabel(parsed.priority),
                        color: priorityColor(parsed.priority)
                    )
                }

                // 반복 칩
                if let rule = parsed.repeatRule {
                    PreviewChip(
                        icon: "repeat",
                        text: repeatLabel(rule),
                        color: .purple
                    )
                }
            }
            .padding(.horizontal, Theme.spacingM)
        }
    }

    private func priorityLabel(_ p: Int) -> String {
        switch p {
        case 3: return "높음"
        case 2: return "보통"
        case 1: return "낮음"
        default: return ""
        }
    }

    private func priorityColor(_ p: Int) -> Color {
        switch p {
        case 3: return .red
        case 2: return .orange
        default: return .blue
        }
    }

    private func repeatLabel(_ rule: String) -> String {
        if rule.contains("DAILY") { return "매일" }
        if rule.contains("WEEKLY") { return "매주" }
        if rule.contains("MONTHLY") { return "매월" }
        return "반복"
    }
}

// MARK: - Budget 파싱 결과 미리보기

struct BudgetPreviewChips: View {
    let parsed: ParsedBudgetInput

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.spacingS) {
                // 상호명 칩
                PreviewChip(
                    icon: "storefront",
                    text: parsed.merchant.isEmpty ? "알 수 없음" : parsed.merchant,
                    color: .indigo
                )

                // 금액 칩
                let isExpense = parsed.type == "expense"
                PreviewChip(
                    icon: isExpense ? "minus.circle.fill" : "plus.circle.fill",
                    text: parsed.amount.formattedKRW(),
                    color: isExpense ? Theme.expenseRed : Theme.incomeGreen
                )

                // 카테고리 칩
                PreviewChip(
                    icon: BudgetCategory(rawValue: parsed.category)?.icon ?? "tag",
                    text: parsed.category,
                    color: .teal
                )

                // 날짜 칩
                if let date = parseISODate(parsed.dateISO) {
                    PreviewChip(
                        icon: "calendar",
                        text: Calendar.current.isDateInToday(date) ? "오늘" : date.formatted(.dateTime.month().day()),
                        color: .gray
                    )
                }
            }
            .padding(.horizontal, Theme.spacingM)
        }
    }
}

// MARK: - 공통 칩 컴포넌트

struct PreviewChip: View {
    let icon: String
    let text: String
    let color: Color
    var action: (() -> Void)? = nil

    var body: some View {
        Button(action: { action?() }) {
            Label(text, systemImage: icon)
                .font(Theme.caption().bold())
                .foregroundStyle(color)
                .padding(.horizontal, Theme.spacingS)
                .padding(.vertical, 6)
                .background(color.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

// MARK: - 로딩 shimmer 칩

struct ShimmerChips: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: Theme.spacingS) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.gray.opacity(animating ? 0.15 : 0.3))
                    .frame(width: CGFloat([80, 100, 70][i]), height: 28)
                    .animation(
                        .easeInOut(duration: 0.8).repeatForever().delay(Double(i) * 0.15),
                        value: animating
                    )
            }
        }
        .padding(.horizontal, Theme.spacingM)
        .onAppear { animating = true }
    }
}
