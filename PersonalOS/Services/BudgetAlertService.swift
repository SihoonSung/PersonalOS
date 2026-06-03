import Foundation
import SwiftData
import UserNotifications

enum BudgetAlertService {
    static func check(
        context: ModelContext,
        defaultCurrency: String = UserDefaults.standard.string(forKey: "defaultCurrency") ?? Currency.krw.rawValue,
        monthlyBudget: Double = UserDefaults.standard.double(forKey: "monthlyBudget"),
        alertsEnabled: Bool = UserDefaults.standard.object(forKey: "budgetAlertEnabled") as? Bool ?? true
    ) {
        guard alertsEnabled, monthlyBudget > 0 else { return }

        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: .now)) ?? .now
        let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) ?? .distantFuture
        let expenseType = EntryType.expense.rawValue
        var descriptor = FetchDescriptor<BudgetEntry>(
            predicate: #Predicate {
                $0.type == expenseType &&
                $0.currency == defaultCurrency &&
                $0.date >= monthStart &&
                $0.date < monthEnd
            }
        )
        descriptor.propertiesToFetch = [\.amount]
        let entries = (try? context.fetch(descriptor)) ?? []
        let monthSpend = entries.reduce(0) { $0 + $1.amount }

        guard monthSpend > monthlyBudget else { return }

        let monthKey = monthStart.formatted(.dateTime.year().month(.twoDigits).locale(Locale(identifier: "en_US_POSIX")))
        let notificationKey = "budgetAlertSentMonth-\(defaultCurrency)"
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: notificationKey) != monthKey else { return }

        Task {
            let granted = await NotificationService.requestPermission()
            guard granted else { return }

            let currency = Currency(rawValue: defaultCurrency) ?? .krw
            let content = UNMutableNotificationContent()
            content.title = L.budgetAlertTitle
            content.body = L.budgetAlertBody(
                currency.format(monthSpend - monthlyBudget),
                currency.format(monthSpend),
                currency.format(monthlyBudget)
            )
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "budget-alert-\(monthKey)-\(defaultCurrency)",
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
            defaults.set(monthKey, forKey: notificationKey)
        }
    }
}
