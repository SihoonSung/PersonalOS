import Foundation
import SwiftData
#if canImport(WidgetKit)
import WidgetKit
#endif

/// 위젯용 스냅샷 생성 — 데이터 변경 시점마다 호출.
enum WidgetDataWriter {

    @MainActor
    static func refresh(context: ModelContext) {
        guard let url = WidgetShared.snapshotURL else { return }

        var snapshot = WidgetSnapshot()
        let databases = (try? context.fetch(FetchDescriptor<POSDatabase>())) ?? []
        let calendar = Calendar.current

        // ── 오늘 할 일 ──
        if let todo = databases.first(where: { $0.templateKey == TemplateKey.todo })
            ?? databases.first(where: { $0.doneProperty != nil }) {
            if let doneProp = todo.doneProperty {
                let dateProp = todo.dateProperty
                let startOfToday = calendar.startOfDay(for: .now)
                var focus: [(POSEntry, Date, Bool)] = []
                for entry in todo.entries ?? [] {
                    if entry.bool(for: doneProp) {
                        if calendar.isDateInToday(entry.updatedAt) { snapshot.doneToday += 1 }
                        continue
                    }
                    guard let due = dateProp.flatMap({ entry.date(for: $0) }) else { continue }
                    let overdue = due < startOfToday
                    guard overdue || calendar.isDateInToday(due) else { continue }
                    focus.append((entry, due, overdue))
                }
                focus.sort { $0.1 < $1.1 }
                snapshot.totalToday = focus.count + snapshot.doneToday
                let includeTime = todo.dateProperty?.config.includeTime == true
                snapshot.tasks = focus.prefix(4).map { entry, due, overdue in
                    WidgetSnapshot.Task(
                        id: entry.uuid.uuidString,
                        title: entry.title.isEmpty ? "(제목 없음)" : entry.title,
                        overdue: overdue,
                        timeText: (!overdue && includeTime)
                            ? due.formatted(.dateTime.hour().minute())
                            : nil
                    )
                }
            }
        }

        // ── 예산 ──
        if let budget = databases.first(where: { $0.templateKey == TemplateKey.budget }) {
            let dateProp = budget.dateProperty
            let amountProp = budget.amountProperty
            let spent = (budget.entries ?? []).reduce(0.0) { partial, entry in
                let date = dateProp.flatMap { entry.date(for: $0) } ?? entry.createdAt
                guard calendar.isDate(date, equalTo: .now, toGranularity: .month) else { return partial }
                return partial + (amountProp.flatMap { entry.number(for: $0) } ?? 0)
            }
            let monthlyBudget = UserDefaults.standard.double(forKey: "monthlyBudget")
            snapshot.monthSpentText = budget.formattedAmount(spent)
            if monthlyBudget > 0 {
                snapshot.budgetSet = true
                snapshot.remainingText = budget.formattedAmount(monthlyBudget - spent)
                snapshot.budgetProgress = min(spent / monthlyBudget, 1.0)
                snapshot.overBudget = spent > monthlyBudget
            }
        }

        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
