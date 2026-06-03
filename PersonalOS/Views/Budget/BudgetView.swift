import SwiftUI
import SwiftData

struct BudgetView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BudgetEntry.date, order: .reverse) private var allEntries: [BudgetEntry]
    @AppStorage("defaultCurrency") private var defaultCurrency: String = Currency.krw.rawValue
    @AppStorage("monthlyBudget") private var monthlyBudget: Double = 0

    @State private var selectedMonth: Date = {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: .now))!
    }()
    @State private var selectedTab: BudgetTab = .overview
    @State private var showAddSheet = false
    @State private var showRecurring = false
    @State private var selectedEntry: BudgetEntry?
    @State private var searchText = ""
    @State private var typeFilter: BudgetTypeFilter = .all
    @State private var categoryFilter: BudgetCategory?
    @State private var currencyFilter: String?
    @State private var exportFile: BudgetExportFile?

    private var monthEntries: [BudgetEntry] {
        let cal = Calendar.current
        let start = selectedMonth
        guard let end = cal.date(byAdding: .month, value: 1, to: start) else { return [] }
        return allEntries.filter { $0.date >= start && $0.date < end }
    }

    private var filteredEntries: [BudgetEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return monthEntries.filter { entry in
            if typeFilter == .expense && !entry.isExpense { return false }
            if typeFilter == .income && entry.isExpense { return false }
            if let categoryFilter, entry.budgetCategory != categoryFilter { return false }
            if let currencyFilter, entry.currency != currencyFilter { return false }
            guard !query.isEmpty else { return true }

            return entry.merchant.lowercased().contains(query)
                || entry.note.lowercased().contains(query)
                || entry.budgetCategory.localizedName.lowercased().contains(query)
                || (entry.rawInput ?? "").lowercased().contains(query)
        }
    }

    private var groupedFilteredEntries: [(Date, [BudgetEntry])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: filteredEntries) { entry in
            cal.startOfDay(for: entry.date)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    private var filtersAreActive: Bool {
        !searchText.isEmpty || typeFilter != .all || categoryFilter != nil || currencyFilter != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 투자 탭에서는 월 피커 불필요
                if selectedTab != .investment {
                    MonthPickerHeader(selectedMonth: $selectedMonth)
                }

                Picker("", selection: $selectedTab) {
                    ForEach(BudgetTab.allCases, id: \.self) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.spacingM)
                .padding(.bottom, Theme.spacingS)

                switch selectedTab {
                case .overview:
                    BudgetOverviewView(
                        entries: monthEntries,
                        allEntries: allEntries,
                        monthStart: selectedMonth,
                        monthlyBudget: monthlyBudget,
                        defaultCurrency: defaultCurrency,
                        showAddSheet: $showAddSheet,
                        selectedEntry: $selectedEntry
                    )
                case .records:
                    recordsView
                case .analytics:
                    BudgetAnalyticsView(
                        entries: monthEntries,
                        monthlyBudget: monthlyBudget,
                        defaultCurrency: defaultCurrency,
                        selectedEntry: $selectedEntry
                    )
                case .investment:
                    InvestmentView()
                }
            }
            .navigationTitle(L.budgetNavTitle)
            .toolbar {
                if selectedTab != .investment {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showRecurring = true } label: {
                            Label(L.budgetRoutineBtn, systemImage: "repeat.circle")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                exportMonth()
                            } label: {
                                Label(L.budgetExportCSV, systemImage: "square.and.arrow.up")
                            }
                            Button {
                                showAddSheet = true
                            } label: {
                                Label(L.budgetAddBtn, systemImage: "plus")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle").font(.title3)
                        }
                    }
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: L.budgetSearchPrompt
            )
            .sheet(isPresented: $showAddSheet) {
                AddBudgetSheet()
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $selectedEntry) { entry in
                BudgetDetailView(entry: entry)
                    .presentationDetents([.medium])
            }
            .sheet(item: $exportFile) { file in
                BudgetExportSheet(file: file)
                    .presentationDetents([.height(180)])
            }
            .navigationDestination(isPresented: $showRecurring) {
                RecurringView()
            }
        }
    }

    private var recordsView: some View {
        VStack(spacing: 0) {
            BudgetFilterBar(
                typeFilter: $typeFilter,
                categoryFilter: $categoryFilter,
                currencyFilter: $currencyFilter,
                filtersAreActive: filtersAreActive,
                reset: resetFilters
            )

            if monthEntries.isEmpty {
                BudgetEmptyState(title: L.budgetEmptyTitle, hint: L.budgetEmptyHint) {
                    showAddSheet = true
                }
            } else if filteredEntries.isEmpty {
                BudgetEmptyState(title: L.budgetNoFilteredResults, hint: L.budgetSearchPrompt) {
                    resetFilters()
                }
            } else {
                List {
                    Section {
                        HStack {
                            Text(L.budgetRecordsCount(filteredEntries.count))
                                .font(Theme.caption())
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }

                    ForEach(groupedFilteredEntries, id: \.0) { date, entries in
                        Section(sectionTitle(for: date)) {
                            ForEach(entries) { entry in
                                BudgetRowView(entry: entry)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedEntry = entry }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            delete(entry)
                                        } label: {
                                            Label(L.recurringSwipeDelete, systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func sectionTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L.locale
        formatter.setLocalizedDateFormatFromTemplate("MMMdEEE")
        return formatter.string(from: date)
    }

    private func resetFilters() {
        searchText = ""
        typeFilter = .all
        categoryFilter = nil
        currencyFilter = nil
    }

    private func delete(_ entry: BudgetEntry) {
        context.delete(entry)
        try? context.save()
        WidgetDataWriter.refresh(context: context, defaultCurrency: defaultCurrency)
        BudgetAlertService.check(context: context)
    }

    private func exportMonth() {
        guard let url = try? BudgetExportService.makeCSVFile(entries: monthEntries, month: selectedMonth) else {
            return
        }
        exportFile = BudgetExportFile(url: url)
    }
}

private enum BudgetTab: CaseIterable {
    case overview
    case records
    case analytics
    case investment

    var title: String {
        switch self {
        case .overview:    return L.budgetOverviewTab
        case .records:     return L.budgetRecordsTab
        case .analytics:   return L.budgetAnalyticsTab
        case .investment:  return L.investmentSegment
        }
    }
}

private enum BudgetTypeFilter: CaseIterable {
    case all
    case expense
    case income

    var title: String {
        switch self {
        case .all: return L.budgetAllTypes
        case .expense: return L.budgetFilterExpense
        case .income: return L.budgetFilterIncome
        }
    }
}

private struct BudgetExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct BudgetExportSheet: View {
    let file: BudgetExportFile

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.spacingM) {
                Image(systemName: "doc.text")
                    .font(.largeTitle)
                    .foregroundStyle(.blue)
                Text(file.url.lastPathComponent)
                    .font(Theme.body())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                ShareLink(item: file.url) {
                    Label(L.budgetExportShare, systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(Theme.spacingM)
            .navigationTitle(L.budgetExportReady)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Overview

private struct BudgetOverviewView: View {
    let entries: [BudgetEntry]
    let allEntries: [BudgetEntry]
    let monthStart: Date
    let monthlyBudget: Double
    let defaultCurrency: String
    @Binding var showAddSheet: Bool
    @Binding var selectedEntry: BudgetEntry?

    private var recentEntries: [BudgetEntry] { Array(entries.prefix(5)) }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacingM) {
                MonthSummaryBanner(entries: entries, allEntries: allEntries, monthStart: monthStart)
                BudgetProgressPanel(entries: entries, monthlyBudget: monthlyBudget, defaultCurrency: defaultCurrency)

                if entries.isEmpty {
                    BudgetEmptyState(title: L.budgetEmptyTitle, hint: L.budgetEmptyHint) {
                        showAddSheet = true
                    }
                    .frame(minHeight: 260)
                } else {
                    BudgetCategoryBreakdownView(entries: entries, defaultCurrency: defaultCurrency, compact: true)

                    VStack(alignment: .leading, spacing: Theme.spacingS) {
                        Text(L.budgetRecordsTab)
                            .font(Theme.headline())
                        ForEach(recentEntries) { entry in
                            Button {
                                selectedEntry = entry
                            } label: {
                                BudgetRowView(entry: entry)
                                    .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                            if entry.id != recentEntries.last?.id {
                                Divider()
                            }
                        }
                    }
                    .cardStyle()
                }
            }
            .padding(Theme.spacingM)
        }
        .background(Theme.groupedBackground)
    }
}

// MARK: - Records

private struct BudgetFilterBar: View {
    @Binding var typeFilter: BudgetTypeFilter
    @Binding var categoryFilter: BudgetCategory?
    @Binding var currencyFilter: String?
    let filtersAreActive: Bool
    let reset: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.spacingS) {
                Menu {
                    ForEach(BudgetTypeFilter.allCases, id: \.self) { filter in
                        Button(filter.title) { typeFilter = filter }
                    }
                } label: {
                    FilterPill(title: typeFilter.title, icon: "line.3.horizontal.decrease.circle")
                }

                Menu {
                    Button(L.budgetAllCategories) { categoryFilter = nil }
                    Divider()
                    ForEach(BudgetCategory.allCases, id: \.rawValue) { category in
                        Button(category.localizedName) { categoryFilter = category }
                    }
                } label: {
                    FilterPill(title: categoryFilter?.localizedName ?? L.budgetAllCategories, icon: categoryFilter?.icon ?? "square.grid.2x2")
                }

                Menu {
                    Button(L.budgetAllCurrencies) { currencyFilter = nil }
                    Divider()
                    ForEach(Currency.allCases, id: \.rawValue) { currency in
                        Button(currency.label) { currencyFilter = currency.rawValue }
                    }
                } label: {
                    let currency = currencyFilter.flatMap(Currency.init(rawValue:))
                    FilterPill(title: currency?.label ?? L.budgetAllCurrencies, icon: "dollarsign.circle")
                }

                if filtersAreActive {
                    Button {
                        reset()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.spacingM)
            .padding(.vertical, Theme.spacingS)
        }
        .background(Theme.groupedBackground)
    }
}

private struct FilterPill: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(Theme.caption().bold())
            .lineLimit(1)
            .padding(.horizontal, Theme.spacingS)
            .padding(.vertical, 7)
            .background(Theme.secondaryBackground)
            .clipShape(Capsule())
    }
}

// MARK: - Analytics

private struct BudgetAnalyticsView: View {
    let entries: [BudgetEntry]
    let monthlyBudget: Double
    let defaultCurrency: String
    @Binding var selectedEntry: BudgetEntry?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacingM) {
                BudgetProgressPanel(entries: entries, monthlyBudget: monthlyBudget, defaultCurrency: defaultCurrency)
                BudgetCategoryBreakdownView(entries: entries, defaultCurrency: defaultCurrency, compact: false)
                LargestExpensesView(entries: entries, defaultCurrency: defaultCurrency, selectedEntry: $selectedEntry)
            }
            .padding(Theme.spacingM)
        }
        .background(Theme.groupedBackground)
    }
}

private struct BudgetProgressPanel: View {
    let entries: [BudgetEntry]
    let monthlyBudget: Double
    let defaultCurrency: String

    private var currency: Currency { Currency(rawValue: defaultCurrency) ?? .krw }
    private var monthSpend: Double {
        entries.filter { $0.isExpense && $0.currency == defaultCurrency }.reduce(0) { $0 + $1.amount }
    }
    private var progress: Double {
        guard monthlyBudget > 0 else { return 0 }
        return min(monthSpend / monthlyBudget, 1)
    }
    private var isOver: Bool { monthlyBudget > 0 && monthSpend > monthlyBudget }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            HStack {
                Text(L.budgetBudgetProgress)
                    .font(Theme.headline())
                Spacer()
                if monthlyBudget > 0 {
                    Text(L.budgetPercentUsed(Int((monthSpend / monthlyBudget * 100).rounded())))
                        .font(Theme.caption().bold())
                        .foregroundStyle(isOver ? Theme.expenseRed : .secondary)
                }
            }

            if monthlyBudget > 0 {
                ProgressView(value: progress)
                    .tint(isOver ? Theme.expenseRed : .blue)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isOver ? L.budgetOverAmount : L.budgetRemaining)
                            .font(Theme.caption2())
                            .foregroundStyle(.secondary)
                        Text(currency.format(abs(monthlyBudget - monthSpend)))
                            .font(Theme.body().bold())
                            .foregroundStyle(isOver ? Theme.expenseRed : Theme.incomeGreen)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(currency.format(monthSpend)) / \(currency.format(monthlyBudget))")
                            .font(Theme.caption())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
            } else {
                Text(L.budgetNoBudgetSet)
                    .font(Theme.body())
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }
}

private struct BudgetCategoryBreakdownView: View {
    let entries: [BudgetEntry]
    let defaultCurrency: String
    let compact: Bool

    private var currency: Currency { Currency(rawValue: defaultCurrency) ?? .krw }
    private var expenses: [BudgetEntry] {
        entries.filter { $0.isExpense && $0.currency == defaultCurrency }
    }
    private var total: Double {
        expenses.reduce(0) { $0 + $1.amount }
    }
    private var rows: [(category: BudgetCategory, amount: Double)] {
        let grouped = Dictionary(grouping: expenses) { $0.budgetCategory }
        return grouped.map { ($0.key, $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.1 > $1.1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            Text(L.budgetCategoryBreakdown)
                .font(Theme.headline())

            if rows.isEmpty {
                Text(L.budgetNoAnalytics)
                    .font(Theme.body())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Theme.spacingM)
            } else {
                ForEach(Array(rows.prefix(compact ? 4 : rows.count)), id: \.category.rawValue) { row in
                    let percent = total > 0 ? row.amount / total : 0
                    CategorySpendRow(
                        category: row.category,
                        subtitle: L.budgetCategoryShare(currency.format(row.amount), Int((percent * 100).rounded())),
                        progress: percent
                    )
                }
            }
        }
        .cardStyle()
    }
}

private struct CategorySpendRow: View {
    let category: BudgetCategory
    let subtitle: String
    let progress: Double

    var body: some View {
        VStack(spacing: Theme.spacingXS) {
            HStack(spacing: Theme.spacingS) {
                Image(systemName: category.icon)
                    .foregroundStyle(category.color)
                    .frame(width: 24)
                Text(category.localizedName)
                    .font(Theme.body())
                Spacer()
                Text(subtitle)
                    .font(Theme.caption())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.14))
                    Capsule()
                        .fill(category.color)
                        .frame(width: max(4, proxy.size.width * progress))
                }
            }
            .frame(height: 6)
        }
    }
}

private struct LargestExpensesView: View {
    let entries: [BudgetEntry]
    let defaultCurrency: String
    @Binding var selectedEntry: BudgetEntry?

    private var largest: [BudgetEntry] {
        Array(entries.filter { $0.isExpense && $0.currency == defaultCurrency }
            .sorted { $0.amount > $1.amount }
            .prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            Text(L.budgetLargestEntries)
                .font(Theme.headline())

            if largest.isEmpty {
                Text(L.budgetNoAnalytics)
                    .font(Theme.body())
                    .foregroundStyle(.secondary)
                    .padding(.vertical, Theme.spacingM)
            } else {
                ForEach(largest) { entry in
                    Button {
                        selectedEntry = entry
                    } label: {
                        BudgetRowView(entry: entry)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    if entry.id != largest.last?.id {
                        Divider()
                    }
                }
            }
        }
        .cardStyle()
    }
}

// MARK: - Shared

private struct MonthPickerHeader: View {
    @Binding var selectedMonth: Date

    private var displayString: String {
        selectedMonth.formatted(.dateTime.year().month().locale(L.locale))
    }

    var body: some View {
        HStack {
            Button {
                adjustMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
            }

            Spacer()

            Text(displayString)
                .font(Theme.headline())

            Spacer()

            Button {
                adjustMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
            }
            .disabled(isCurrentMonth)
        }
        .padding(.horizontal, Theme.spacingL)
        .padding(.vertical, Theme.spacingS)
    }

    private var isCurrentMonth: Bool {
        Calendar.current.isDate(selectedMonth, equalTo: .now, toGranularity: .month)
    }

    private func adjustMonth(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: value, to: selectedMonth) {
            selectedMonth = newDate
        }
    }
}

private struct MonthSummaryBanner: View {
    let entries: [BudgetEntry]
    let allEntries: [BudgetEntry]
    let monthStart: Date

    private var krwExpense: Double { entries.filter { $0.isExpense && $0.currency == "KRW" }.reduce(0) { $0 + $1.amount } }
    private var usdExpense: Double { entries.filter { $0.isExpense && $0.currency == "USD" }.reduce(0) { $0 + $1.amount } }
    private var krwIncome: Double { entries.filter { !$0.isExpense && $0.currency == "KRW" }.reduce(0) { $0 + $1.amount } }
    private var usdIncome: Double { entries.filter { !$0.isExpense && $0.currency == "USD" }.reduce(0) { $0 + $1.amount } }
    private var krwCarryover: Double { carryover(for: "KRW") }
    private var usdCarryover: Double { carryover(for: "USD") }
    private var hasKRW: Bool { krwExpense > 0 || krwIncome > 0 || krwCarryover != 0 }
    private var hasUSD: Bool { usdExpense > 0 || usdIncome > 0 || usdCarryover != 0 }
    private var hasMixed: Bool { hasKRW && hasUSD }

    var body: some View {
        VStack(spacing: Theme.spacingXS) {
            if hasMixed {
                summaryRow(expense: krwExpense, income: krwIncome, carryover: krwCarryover, format: Currency.krw.format)
                Divider()
                summaryRow(expense: usdExpense, income: usdIncome, carryover: usdCarryover, format: Currency.usd.format)
            } else if hasUSD {
                summaryRow(expense: usdExpense, income: usdIncome, carryover: usdCarryover, format: Currency.usd.format)
            } else {
                summaryRow(expense: krwExpense, income: krwIncome, carryover: krwCarryover, format: Currency.krw.format)
            }
        }
        .cardStyle()
    }

    private func summaryRow(expense: Double, income: Double, carryover: Double, format: (Double) -> String) -> some View {
        let net = income - expense
        let total = carryover + net

        return VStack(spacing: Theme.spacingS) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.budgetTotalBalance)
                        .font(Theme.caption2())
                        .foregroundStyle(.secondary)
                    Text(balanceText(total, format: format))
                        .font(.title3.bold())
                        .foregroundStyle(total >= 0 ? Theme.incomeGreen : Theme.expenseRed)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(L.budgetCarryover)
                        .font(Theme.caption2())
                        .foregroundStyle(.secondary)
                    Text(balanceText(carryover, format: format))
                        .font(Theme.caption().bold())
                        .foregroundStyle(carryover >= 0 ? .secondary : Theme.expenseRed)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            Divider()

            HStack {
                SummaryItem(title: L.budgetExpense, text: format(expense), color: Theme.expenseRed)
                Divider().frame(height: 40)
                SummaryItem(title: L.budgetIncome, text: format(income), color: Theme.incomeGreen)
                Divider().frame(height: 40)
                SummaryItem(title: L.budgetNet, text: format(abs(net)), color: net >= 0 ? Theme.incomeGreen : Theme.expenseRed)
            }
        }
    }

    private func carryover(for currency: String) -> Double {
        allEntries
            .filter { $0.currency == currency && $0.date < monthStart }
            .reduce(0) { partial, entry in
                partial + (entry.isExpense ? -entry.amount : entry.amount)
            }
    }

    private func balanceText(_ amount: Double, format: (Double) -> String) -> String {
        amount >= 0 ? format(amount) : "-\(format(abs(amount)))"
    }
}

private struct SummaryItem: View {
    let title: String
    let text: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(text)
                .font(.callout.bold())
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(Theme.caption2())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BudgetEmptyState: View {
    let title: String
    let hint: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: Theme.spacingM) {
            Spacer()
            Image(systemName: "creditcard")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text(title)
                .font(Theme.headline())
                .multilineTextAlignment(.center)
            Text(hint)
                .font(Theme.body())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L.budgetAddBtn) { action() }
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding(Theme.spacingXL)
    }
}

private extension BudgetCategory {
    var color: Color {
        switch self {
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
