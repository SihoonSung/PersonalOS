import SwiftUI
import SwiftData

// MARK: - 반폭 요약 카드 (예산 · 오늘 지출)
//
// 공통 패턴: caption bold secondary 제목 → title3 bold 큰 숫자 →
// caption2 보조(의미 있을 때만 컬러) → 씬 바 or 칩 행

/// 이번 달 예산 글래스 카드 — 남은 예산 + 사용률 씬 바
struct BudgetSummaryCard: View {
    let database: POSDatabase
    var onOpen: () -> Void = {}

    @AppStorage("monthlyBudget") private var monthlyBudget: Double = 0
    @AppStorage(AmountPrivacy.key) private var hideAmounts = false

    private var calendar: Calendar { .current }

    private var monthSpend: Double {
        let dateProp = database.dateProperty
        let amountProp = database.amountProperty
        return (database.entries ?? []).reduce(0) { partial, entry in
            guard entry.countsAsSpending(in: database) else { return partial }
            let date = dateProp.flatMap { entry.date(for: $0) } ?? entry.createdAt
            guard calendar.isDate(date, equalTo: .now, toGranularity: .month) else { return partial }
            return partial + (amountProp.flatMap { entry.number(for: $0) } ?? 0)
        }
    }

    /// 설정값 + 이번 달 받은 정산. BudgetMath.swift 설명 참고.
    private var effectiveBudget: Double {
        BudgetMath.effective(base: monthlyBudget, database: database, month: .now, calendar: calendar)
    }

    private var progress: Double {
        guard effectiveBudget > 0 else { return 0 }
        return min(monthSpend / effectiveBudget, 1.0)
    }

    private var isOver: Bool { effectiveBudget > 0 && monthSpend > effectiveBudget }

    var body: some View {
        let spend = monthSpend
        let budget = effectiveBudget

        VStack(alignment: .leading, spacing: Theme.spacingS) {
            HStack {
                Text(L.dashBudgetTitle)
                    .font(Theme.caption().bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onOpen) {
                    Image(systemName: "chevron.right")
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(database.formattedAmount(budget > 0 ? budget - spend : spend))
                .font(.title3.bold())
                .foregroundStyle(budget > 0 && spend > budget ? Theme.expenseRed : Color.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if budget > 0 {
                if isOver {
                    Text(L.dashBudgetOver(database.formattedAmount(spend - budget)))
                        .font(Theme.caption2().bold())
                        .foregroundStyle(.orange)
                } else {
                    Text(L.dashBudgetUsed(Int(progress * 100)))
                        .font(Theme.caption2())
                        .foregroundStyle(.secondary)
                }

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.glassTrack)
                    GeometryReader { geo in
                        Capsule()
                            .fill(isOver ? AnyShapeStyle(Color.orange) : AnyShapeStyle(Theme.glassInk.opacity(0.75)))
                            .frame(width: geo.size.width * progress)
                            .animation(.spring(duration: 0.5), value: progress)
                    }
                }
                .frame(height: 5)
            } else {
                Text(L.dashMonthSpent)
                    .font(Theme.caption2())
                    .foregroundStyle(.secondary)

                Text("설정에서 월 예산을 정할 수 있어요")
                    .font(Theme.caption2())
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle()
    }
}

/// 오늘 지출 글래스 카드 — 오늘 합계 + 이번 주 + 카테고리 칩
struct TodaySpendCard: View {
    let database: POSDatabase

    private var calendar: Calendar { .current }

    private struct Row {
        let date: Date
        let amount: Double
        let category: String
    }

    private var rows: [Row] {
        let dateProp = database.dateProperty
        let amountProp = database.amountProperty
        let categoryProp = database.categoryProperty
        return (database.entries ?? []).filter { $0.countsAsSpending(in: database) }.map { entry in
            Row(
                date: dateProp.flatMap { entry.date(for: $0) } ?? entry.createdAt,
                amount: amountProp.flatMap { entry.number(for: $0) } ?? 0,
                category: categoryProp.flatMap { entry.text(for: $0) } ?? ""
            )
        }
    }

    var body: some View {
        let all = rows
        let today = all.filter { calendar.isDateInToday($0.date) }.map(\.amount).reduce(0, +)
        let week = all.filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear) }
            .map(\.amount).reduce(0, +)
        let topCategories = Dictionary(
            grouping: all.filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .month) && !$0.category.isEmpty },
            by: \.category
        )
        .map { (name: $0.key, total: $0.value.map(\.amount).reduce(0, +)) }
        .sorted { $0.total > $1.total }
        .prefix(3)

        VStack(alignment: .leading, spacing: Theme.spacingS) {
            Text(L.dashTodaySpent)
                .font(Theme.caption().bold())
                .foregroundStyle(.secondary)

            Text(database.formattedAmount(today))
                .font(.title3.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(L.dashWeekSpent(database.formattedAmount(week)))
                .font(Theme.caption2())
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if !topCategories.isEmpty {
                HStack(spacing: Theme.spacingXS) {
                    ForEach(topCategories, id: \.name) { item in
                        Text(item.name)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.glassTrack, in: Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle()
    }
}
