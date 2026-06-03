import Foundation
import SwiftData

final class RecurringService {
    // 앱 시작 시 호출 — 이번 달 적용 안 된 활성 루틴을 BudgetEntry로 생성
    static func applyIfNeeded(context: ModelContext) {
        let cal = Calendar.current
        let now = Date.now
        let currentMonthKey = monthKey(from: now)
        let todayDay = cal.component(.day, from: now)

        let descriptor = FetchDescriptor<RecurringEntry>(
            predicate: #Predicate { $0.isActive }
        )
        guard let entries = try? context.fetch(descriptor) else { return }

        for entry in entries {
            let lastDayOfMonth = cal.range(of: .day, in: .month, for: now)?.count ?? 28
            let effectiveDay = min(max(entry.dayOfMonth, 1), lastDayOfMonth)

            // 이미 이번 달 적용됐으면 스킵
            guard entry.lastAppliedMonth != currentMonthKey else { continue }
            // 지정한 날짜가 아직 안 지났으면 스킵
            guard todayDay >= effectiveDay else { continue }
            // 이번 달에 생성됐고 지정일이 이미 지났다면 이번 달은 적용済로 처리한다.
            // 예: 6/20에 매월 15일 루틴을 만들면 6/15 기록을 뒤늦게 만들지 않는다.
            let entryCreatedInCurrentMonth = monthKey(from: entry.createdAt) == currentMonthKey
            if entryCreatedInCurrentMonth {
                let createdDay = cal.component(.day, from: entry.createdAt)
                guard createdDay <= effectiveDay else {
                    entry.lastAppliedMonth = currentMonthKey
                    continue
                }
            }

            // 실제 적용 날짜 계산 (이번 달 N일, 없으면 말일)
            let components = DateComponents(
                year: cal.component(.year, from: now),
                month: cal.component(.month, from: now),
                day: effectiveDay
            )
            let applyDate = cal.date(from: components) ?? now

            let budget = BudgetEntry(
                amount: entry.amount,
                currency: entry.currencyEnum,
                type: entry.isExpense ? .expense : .income,
                merchant: entry.title,
                category: entry.budgetCategory,
                note: L.recurringAutoNote,
                date: applyDate
            )
            context.insert(budget)
            entry.lastAppliedMonth = currentMonthKey
        }

        try? context.save()
        WidgetDataWriter.refresh(context: context)
        BudgetAlertService.check(context: context)
    }

    private static func monthKey(from date: Date) -> String {
        let cal = Calendar.current
        let year = cal.component(.year, from: date)
        let month = cal.component(.month, from: date)
        return "\(year)-\(String(format: "%02d", month))"
    }
}
