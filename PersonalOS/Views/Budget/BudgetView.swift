import SwiftUI
import SwiftData

struct BudgetView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BudgetEntry.date, order: .reverse) private var allEntries: [BudgetEntry]

    @State private var selectedMonth: Date = {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: .now))!
    }()
    @State private var showAddSheet = false
    @State private var selectedEntry: BudgetEntry?

    private var monthEntries: [BudgetEntry] {
        let cal = Calendar.current
        let start = selectedMonth
        guard let end = cal.date(byAdding: .month, value: 1, to: start) else { return [] }
        return allEntries.filter { $0.date >= start && $0.date < end }
    }

    private var monthExpense: Double {
        monthEntries.filter { $0.isExpense }.reduce(0) { $0 + $1.amount }
    }

    private var monthIncome: Double {
        monthEntries.filter { !$0.isExpense }.reduce(0) { $0 + $1.amount }
    }

    private var groupedEntries: [(String, [BudgetEntry])] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E)"

        let grouped = Dictionary(grouping: monthEntries) { entry in
            formatter.string(from: entry.date)
        }
        return grouped.sorted { a, b in
            // 날짜 내림차순 정렬
            let fmt = DateFormatter()
            fmt.dateFormat = "M월 d일 (E)"
            fmt.locale = Locale(identifier: "ko_KR")
            let dateA = fmt.date(from: a.key) ?? .distantPast
            let dateB = fmt.date(from: b.key) ?? .distantPast
            return dateA > dateB
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 월 선택 헤더
                MonthPickerHeader(selectedMonth: $selectedMonth)

                // 이번 달 요약
                MonthSummaryBanner(expense: monthExpense, income: monthIncome)
                    .padding(.horizontal, Theme.spacingM)
                    .padding(.vertical, Theme.spacingS)

                Divider()

                // 항목 리스트
                if monthEntries.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(groupedEntries, id: \.0) { dateStr, entries in
                            Section(dateStr) {
                                ForEach(entries) { entry in
                                    BudgetRowView(entry: entry)
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedEntry = entry }
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) {
                                                context.delete(entry)
                                                try? context.save()
                                            } label: {
                                                Label("삭제", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("가계부")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddBudgetSheet()
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $selectedEntry) { entry in
                BudgetDetailView(entry: entry)
                    .presentationDetents([.medium])
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.spacingM) {
            Spacer()
            Image(systemName: "wonsign.circle.dashed")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("이번 달 기록이 없어요")
                .font(Theme.headline())
            Text("'스타벅스 6000원' 형태로 입력해 보세요")
                .font(Theme.body())
                .foregroundStyle(.secondary)
            Button("기록 추가") { showAddSheet = true }
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding(Theme.spacingXL)
    }
}

// MARK: - 월 선택 헤더

private struct MonthPickerHeader: View {
    @Binding var selectedMonth: Date

    private var displayString: String {
        selectedMonth.formatted(.dateTime.year().month().locale(Locale(identifier: "ko_KR")))
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
        let cal = Calendar.current
        return cal.isDate(selectedMonth, equalTo: .now, toGranularity: .month)
    }

    private func adjustMonth(by value: Int) {
        let cal = Calendar.current
        if let newDate = cal.date(byAdding: .month, value: value, to: selectedMonth) {
            selectedMonth = newDate
        }
    }
}

// MARK: - 월별 요약 배너

private struct MonthSummaryBanner: View {
    let expense: Double
    let income: Double

    var net: Double { income - expense }

    var body: some View {
        HStack {
            SummaryItem(title: "지출", amount: expense, color: Theme.expenseRed)
            Divider().frame(height: 40)
            SummaryItem(title: "수입", amount: income, color: Theme.incomeGreen)
            Divider().frame(height: 40)
            SummaryItem(title: "순", amount: net, color: net >= 0 ? Theme.incomeGreen : Theme.expenseRed)
        }
        .padding(Theme.spacingM)
        .background(Theme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))
    }
}

private struct SummaryItem: View {
    let title: String
    let amount: Double
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(amount.formattedKRW())
                .font(.callout.bold())
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(Theme.caption2())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
