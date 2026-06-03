import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage("defaultCurrency") private var defaultCurrency: String = Currency.krw.rawValue
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("monthlyBudget") private var monthlyBudget: Double = 0
    @Environment(AIAvailabilityManager.self) private var aiAvailability
    @Environment(CalendarService.self) private var calendarService

    var body: some View {
        NavigationStack {
            Form {
                Section(L.settingsPersonalSection) {
                    NavigationLink {
                        ProfileSettingsView()
                    } label: {
                        SettingsSummaryRow(
                            icon: "person.circle.fill",
                            tint: .blue,
                            title: L.settingsProfile,
                            detail: userName.isEmpty ? L.settingsProfileEmpty : userName
                        )
                    }
                }

                Section(L.settingsPreferencesSection) {
                    NavigationLink {
                        BudgetSettingsView()
                    } label: {
                        SettingsSummaryRow(
                            icon: "chart.pie.fill",
                            tint: .green,
                            title: L.settingsBudgetSection,
                            detail: budgetSummary
                        )
                    }

                    NavigationLink {
                        CurrencySettingsView()
                    } label: {
                        SettingsSummaryRow(
                            icon: "dollarsign.circle.fill",
                            tint: .orange,
                            title: L.settingsCurrencySection,
                            detail: Currency(rawValue: defaultCurrency)?.label ?? Currency.krw.label
                        )
                    }
                }

                Section(L.settingsIntegrationsSection) {
                    NavigationLink {
                        CalendarSettingsView()
                    } label: {
                        SettingsSummaryRow(
                            icon: "calendar",
                            tint: .red,
                            title: L.calendarSyncTitle,
                            detail: calendarService.isAuthorized ? L.calendarSyncConnected : L.calendarSyncDisconnected
                        )
                    }

                    NavigationLink {
                        AISettingsDetailView(aiAvailability: aiAvailability)
                    } label: {
                        SettingsSummaryRow(
                            icon: "cpu",
                            tint: aiAvailability.isAvailable ? .green : .orange,
                            title: L.settingsAISection,
                            detail: aiAvailability.isAvailable ? L.aiStatusAvailable : L.aiStatusUnavailable
                        )
                    }
                }

                Section(L.settingsAppInfo) {
                    LabeledContent(L.settingsVersion, value: appVersion)
                    LabeledContent(L.settingsStockData, value: "Yahoo Finance")
                    Text(L.settingsLanguageManaged)
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text(L.settingsDisclaimer)
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L.settingsNavTitle)
        }
    }

    private var budgetSummary: String {
        guard monthlyBudget > 0 else { return L.settingsBudgetNotSet }
        let currency = Currency(rawValue: defaultCurrency) ?? .krw
        return currency.format(monthlyBudget)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}

private struct SettingsSummaryRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: Theme.spacingM) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(tint)
                .frame(width: 28)

            Text(title)

            Spacer()

            Text(detail)
                .font(Theme.caption())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

private struct ProfileSettingsView: View {
    @AppStorage("userName") private var userName: String = ""

    var body: some View {
        Form {
            Section(L.settingsProfile) {
                HStack(spacing: Theme.spacingM) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 56, height: 56)
                        Text(userName.isEmpty ? "?" : String(userName.prefix(1)))
                            .font(.title.bold())
                            .foregroundStyle(.blue)
                    }

                    TextField(L.settingsNamePlaceholder, text: $userName)
                        .font(Theme.title())
                }
                .padding(.vertical, Theme.spacingXS)
            }
        }
        .navigationTitle(L.settingsProfile)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BudgetSettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("defaultCurrency") private var defaultCurrency: String = Currency.krw.rawValue
    @AppStorage("monthlyBudget") private var monthlyBudget: Double = 0
    @AppStorage("budgetAlertEnabled") private var budgetAlertEnabled: Bool = true
    @State private var budgetText: String = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(L.settingsBudgetLabel)
                    Spacer()
                    TextField(L.settingsBudgetPlaceholder, text: $budgetText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                        .onChange(of: budgetText) { _, value in
                            monthlyBudget = value.sanitizedDouble ?? 0
                        }
                    Text(Currency(rawValue: defaultCurrency)?.symbol ?? Currency.krw.symbol)
                        .foregroundStyle(.secondary)
                }

                if monthlyBudget > 0 {
                    Button(role: .destructive) {
                        monthlyBudget = 0
                        budgetText = ""
                    } label: {
                        Text(L.settingsBudgetReset)
                    }
                }
            } footer: {
                Text(L.settingsBudgetFooter)
            }

            Section {
                Toggle(L.settingsBudgetAlert, isOn: $budgetAlertEnabled)
            } footer: {
                Text(L.settingsBudgetAlertFooter)
            }
        }
        .navigationTitle(L.settingsBudgetSection)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            budgetText = monthlyBudget > 0 ? String(Int(monthlyBudget)) : ""
        }
        .onChange(of: monthlyBudget) { _, _ in
            BudgetAlertService.check(context: context)
        }
        .onChange(of: budgetAlertEnabled) { _, _ in
            BudgetAlertService.check(context: context)
        }
    }
}

private struct CurrencySettingsView: View {
    @AppStorage("defaultCurrency") private var defaultCurrency: String = Currency.krw.rawValue

    var body: some View {
        Form {
            Section {
                ForEach(Currency.allCases, id: \.rawValue) { currency in
                    Button {
                        defaultCurrency = currency.rawValue
                    } label: {
                        HStack {
                            Text(currency.label)
                                .foregroundStyle(.primary)
                            Spacer()
                            if defaultCurrency == currency.rawValue {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                                    .bold()
                            }
                        }
                    }
                }
            } footer: {
                Text(L.settingsCurrencyFooter)
            }
        }
        .navigationTitle(L.settingsCurrencySection)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CalendarSettingsView: View {
    @Environment(CalendarService.self) private var calendarService

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.red)
                    Text(L.calendarSyncTitle)
                    Spacer()
                    Label(statusText, systemImage: statusIcon)
                        .font(Theme.body())
                        .foregroundStyle(statusColor)
                }

                if !calendarService.isAuthorized {
                    Button {
                        Task { await calendarService.requestAccess() }
                    } label: {
                        Label(L.calendarSyncAllow, systemImage: "calendar.badge.plus")
                    }
                } else {
                    Text(L.calendarSyncDescription)
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(L.calendarSyncTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusColor: Color { calendarService.isAuthorized ? .green : .secondary }
    private var statusIcon: String { calendarService.isAuthorized ? "checkmark.circle.fill" : "circle" }
    private var statusText: String {
        calendarService.isAuthorized ? L.calendarSyncConnected : L.calendarSyncDisconnected
    }
}

private struct AISettingsDetailView: View {
    let aiAvailability: AIAvailabilityManager

    var body: some View {
        Form {
            Section {
                AIStatusRow(aiAvailability: aiAvailability)
            } footer: {
                Text(L.settingsAIFooter)
            }
        }
        .navigationTitle(L.settingsAISection)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AIStatusRow: View {
    let aiAvailability: AIAvailabilityManager

    var statusColor: Color { aiAvailability.isAvailable ? .green : .orange }
    var statusIcon: String { aiAvailability.isAvailable ? "checkmark.circle.fill" : "exclamationmark.circle.fill" }
    var statusText: String { aiAvailability.isAvailable ? L.aiStatusAvailable : L.aiStatusUnavailable }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            HStack {
                Image(systemName: "cpu")
                    .foregroundStyle(.secondary)
                Text(L.aiStatusLabel)
                Spacer()
                Label(statusText, systemImage: statusIcon)
                    .font(Theme.body().bold())
                    .foregroundStyle(statusColor)
            }

            if !aiAvailability.isAvailable {
                Divider()
                HStack(alignment: .top, spacing: Theme.spacingS) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.orange)
                        .font(Theme.caption())
                    Text(aiAvailability.unavailableReason)
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)
                }
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label(L.aiStatusOpenSettings, systemImage: "arrow.up.right.square")
                        .font(Theme.caption().bold())
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
        }
        .padding(.vertical, Theme.spacingXS)
    }
}
