import SwiftUI
import SwiftData

struct RecurringView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RecurringEntry.createdAt) private var entries: [RecurringEntry]
    @State private var showAddSheet = false
    @State private var selected: RecurringEntry?

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(entries) { entry in
                            RecurringRowView(entry: entry)
                                .contentShape(Rectangle())
                                .onTapGesture { selected = entry }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        context.delete(entry)
                                        try? context.save()
                                    } label: {
                                        Label(L.recurringSwipeDelete, systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        entry.isActive.toggle()
                                        try? context.save()
                                    } label: {
                                        Label(
                                            entry.isActive ? L.recurringSwipeDisable : L.recurringSwipeEnable,
                                            systemImage: entry.isActive ? "pause.fill" : "play.fill"
                                        )
                                    }
                                    .tint(entry.isActive ? .orange : .green)
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(L.recurringNavTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddRecurringSheet().presentationDetents([.medium, .large])
            }
            .sheet(item: $selected) { entry in
                AddRecurringSheet(editing: entry).presentationDetents([.medium, .large])
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.spacingM) {
            Spacer()
            Image(systemName: "repeat.circle").font(.system(size: 60)).foregroundStyle(.secondary)
            Text(L.recurringEmptyTitle).font(Theme.headline())
            Text(L.recurringEmptyHint).font(Theme.body()).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(L.recurringAddBtn) { showAddSheet = true }.buttonStyle(.bordered)
            Spacer()
        }
        .padding(Theme.spacingXL)
    }
}

struct RecurringRowView: View {
    let entry: RecurringEntry

    var body: some View {
        HStack(spacing: Theme.spacingM) {
            ZStack {
                Circle()
                    .fill(entry.isActive ? categoryColor.opacity(0.15) : Color.secondary.opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: entry.budgetCategory.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(entry.isActive ? categoryColor : .secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.title).font(Theme.body()).foregroundStyle(entry.isActive ? .primary : .secondary)
                    if !entry.isActive {
                        Text(L.recurringInactiveBadge)
                            .font(Theme.caption2()).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.secondary).clipShape(Capsule())
                    }
                }
                Text(L.recurringDayOfMonth(entry.dayOfMonth))
                    .font(Theme.caption()).foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.currencyEnum.format(entry.amount))
                    .font(Theme.body().monospacedDigit())
                    .foregroundStyle(entry.isExpense ? Theme.expenseRed : Theme.incomeGreen)
                Text(entry.isExpense ? L.recurringExpense : L.recurringIncome)
                    .font(Theme.caption2()).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Theme.spacingXS)
        .opacity(entry.isActive ? 1.0 : 0.6)
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

struct AddRecurringSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultCurrency") private var defaultCurrency: String = Currency.krw.rawValue

    var editing: RecurringEntry? = nil

    @State private var title = ""
    @State private var amountText = ""
    @State private var currency = "KRW"
    @State private var type = "expense"
    @State private var category = BudgetCategory.subscription.rawValue
    @State private var dayOfMonth = 1
    @State private var isActive = true

    var body: some View {
        NavigationStack {
            Form {
                Section(L.addRecurringBasic) {
                    TextField(L.addRecurringNamePlaceholder, text: $title)
                    Picker(L.addRecurringType, selection: $type) {
                        Text(L.addBudgetExpense).tag("expense")
                        Text(L.addBudgetIncome).tag("income")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: type) { _, newType in
                        if newType == "income" && category == BudgetCategory.subscription.rawValue {
                            category = BudgetCategory.salary.rawValue
                        } else if newType == "expense" && category == BudgetCategory.salary.rawValue {
                            category = BudgetCategory.subscription.rawValue
                        }
                    }
                }

                Section(L.addRecurringAmount) {
                    HStack {
                        TextField(L.addRecurringAmountPlaceholder, text: $amountText)
                            .keyboardType(.decimalPad)
                        Picker("", selection: $currency) {
                            ForEach(Currency.allCases, id: \.rawValue) { c in
                                Text(c.symbol).tag(c.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }

                Section(L.addRecurringCategory) {
                    Picker(L.addRecurringCategory, selection: $category) {
                        ForEach(BudgetCategory.allCases, id: \.rawValue) { cat in
                            Label(cat.localizedName, systemImage: cat.icon).tag(cat.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section(L.addRecurringRepeat) {
                    Stepper(L.recurringDayOfMonth(dayOfMonth), value: $dayOfMonth, in: 1...31)
                    Toggle(L.addRecurringActive, isOn: $isActive)
                }
            }
            .navigationTitle(editing == nil ? L.addRecurringNew : L.addRecurringEdit)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { loadEditing() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L.addRecurringCancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.addRecurringSave) { save() }
                        .bold()
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || amountText.isEmpty)
                }
            }
        }
    }

    private func loadEditing() {
        if let e = editing {
            title = e.title
            amountText = e.currency == "USD" ? String(format: "%.2f", e.amount) : String(Int(e.amount))
            currency = Currency(rawValue: e.currency.uppercased())?.rawValue ?? defaultCurrency
            type = e.type
            category = BudgetCategory.from(e.category).rawValue
            dayOfMonth = e.dayOfMonth
            isActive = e.isActive
        } else {
            currency = defaultCurrency
        }
    }

    private func save() {
        let amount = amountText.sanitizedDouble ?? 0
        guard amount > 0 else { return }

        let currencyEnum = Currency(rawValue: currency) ?? .krw
        let typeEnum: EntryType = type == "income" ? .income : .expense
        let categoryEnum = BudgetCategory.from(category)

        if let e = editing {
            e.title = title.trimmingCharacters(in: .whitespaces)
            e.amount = amount
            e.currency = currencyEnum.rawValue
            e.type = typeEnum.rawValue
            e.category = categoryEnum.rawValue
            e.dayOfMonth = dayOfMonth
            e.isActive = isActive
        } else {
            context.insert(RecurringEntry(
                title: title.trimmingCharacters(in: .whitespaces),
                amount: amount, currency: currencyEnum, type: typeEnum,
                category: categoryEnum, dayOfMonth: dayOfMonth, isActive: isActive
            ))
        }
        try? context.save()
        dismiss()
    }
}
