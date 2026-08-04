import SwiftUI
import SwiftData
import Charts

// MARK: - Budget analytics dashboard
//
// 월 단위 분석: 히어로 요약(지난달 같은 기간 대비·일평균·월말 예상),
// 월 예산 진행률, 일별/6개월 추이 차트, 카테고리 분해(바), 인사이트 타일,
// 일자별 내역. 검색 시 전체 월 플랫 리스트.

struct BudgetView: View {
    @Environment(\.modelContext) private var context
    @Bindable var database: POSDatabase
    let searchText: String
    @Binding var editingEntry: POSEntry?

    @State private var monthAnchor: Date = .now
    @AppStorage("monthlyBudget") private var monthlyBudget: Double = 0
    @State private var showingBudgetEditor = false
    @State private var budgetInput = ""
    @State private var showingBalanceEditor = false

    private var calendar: Calendar { .current }

    // MARK: Resolved rows

    private struct Item: Identifiable {
        let entry: POSEntry
        let date: Date
        let amount: Double
        let category: String
        let kind: String
        var id: UUID { entry.uuid }
        var isSpending: Bool { kind == EntryKind.expense }
    }

    /// Every row, 지출/수입/이체 alike. Analytics below narrow to 지출.
    private var everyItem: [Item] {
        let dateProp = database.dateProperty
        let amountProp = database.amountProperty
        let categoryProp = database.categoryProperty
        return (database.entries ?? []).map { entry in
            Item(
                entry: entry,
                date: dateProp.flatMap { entry.date(for: $0) } ?? entry.createdAt,
                amount: amountProp.flatMap { entry.number(for: $0) } ?? 0,
                category: categoryProp.flatMap { entry.text(for: $0) } ?? "기타",
                kind: entry.kind(in: database)
            )
        }
    }

    /// Spending only — 수입과 이체는 지출 합계·예산·차트에서 빠진다.
    private var allItems: [Item] { everyItem.filter(\.isSpending) }

    private var monthItems: [Item] {
        allItems.filter { calendar.isDate($0.date, equalTo: monthAnchor, toGranularity: .month) }
    }

    private var monthTotal: Double { monthItems.map(\.amount).reduce(0, +) }

    /// 실제 수입만 — 정산금은 잔액에는 반영되지만 여기엔 안 잡힌다.
    private var monthIncome: Double {
        everyItem
            .filter { EntryKind.countsAsIncome($0.kind) && calendar.isDate($0.date, equalTo: monthAnchor, toGranularity: .month) }
            .map(\.amount)
            .reduce(0, +)
    }

    private var balance: BalanceSnapshot? {
        BalanceService.snapshot(database: database, context: context)
    }

    /// Imported rows the user hasn't confirmed yet.
    private var unreviewed: [POSEntry] {
        guard let reviewed = database.reviewedProperty else { return [] }
        return (database.entries ?? []).filter { $0.sourceKind == "email" && !$0.bool(for: reviewed) }
    }

    // MARK: Period analytics

    private var isCurrentMonth: Bool {
        calendar.isDate(monthAnchor, equalTo: .now, toGranularity: .month)
    }

    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: monthAnchor)?.count ?? 30
    }

    /// 경과 일수 — 이번 달이면 오늘까지, 과거 달이면 전체.
    private var daysElapsed: Int {
        isCurrentMonth ? calendar.component(.day, from: .now) : daysInMonth
    }

    private var dailyAverage: Double {
        daysElapsed > 0 ? monthTotal / Double(daysElapsed) : 0
    }

    /// 현재 페이스 기준 월말 예상 지출 (이번 달만).
    private var projectedTotal: Double? {
        guard isCurrentMonth, daysElapsed >= 3, monthTotal > 0 else { return nil }
        return dailyAverage * Double(daysInMonth)
    }

    /// 지난달 "같은 기간"(1일~경과일) 지출 — 공정한 비교.
    private var previousSamePeriodTotal: Double {
        guard let prev = calendar.date(byAdding: .month, value: -1, to: monthAnchor) else { return 0 }
        return allItems.filter {
            calendar.isDate($0.date, equalTo: prev, toGranularity: .month)
                && calendar.component(.day, from: $0.date) <= daysElapsed
        }.map(\.amount).reduce(0, +)
    }

    private var deltaPercent: Double? {
        guard previousSamePeriodTotal > 0 else { return nil }
        return (monthTotal - previousSamePeriodTotal) / previousSamePeriodTotal * 100
    }

    // MARK: Chart data

    private var dailyTotals: [(day: Date, total: Double)] {
        Dictionary(grouping: monthItems) { calendar.startOfDay(for: $0.date) }
            .map { ($0.key, $0.value.map(\.amount).reduce(0, +)) }
            .sorted { $0.0 < $1.0 }
    }

    private var trend: [(month: Date, total: Double)] {
        (0..<6).reversed().compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: -offset, to: monthAnchor) else { return nil }
            let total = allItems
                .filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
                .map(\.amount)
                .reduce(0, +)
            return (month, total)
        }
    }

    private var trendAverage: Double {
        let nonZero = trend.filter { $0.total > 0 }
        guard !nonZero.isEmpty else { return 0 }
        return nonZero.map(\.total).reduce(0, +) / Double(nonZero.count)
    }

    private var categoryTotals: [(name: String, total: Double)] {
        Dictionary(grouping: monthItems, by: \.category)
            .map { ($0.key, $0.value.map(\.amount).reduce(0, +)) }
            .sorted { $0.1 > $1.1 }
    }

    // MARK: Insights

    private var topMerchant: (name: String, total: Double)? {
        let named = monthItems.filter { !$0.entry.title.isEmpty }
        return Dictionary(grouping: named) { $0.entry.title }
            .map { ($0.key, $0.value.map(\.amount).reduce(0, +)) }
            .max { $0.1 < $1.1 }
    }

    private var biggestExpense: Item? {
        monthItems.max { $0.amount < $1.amount }
    }

    /// The ledger at the bottom lists everything — hiding 수입 rows there
    /// would make the month look like money vanished.
    private var dayGroups: [(day: Date, items: [Item], total: Double)] {
        let items = everyItem.filter { calendar.isDate($0.date, equalTo: monthAnchor, toGranularity: .month) }
        return Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
            .map { group in
                (
                    group.key,
                    group.value.sorted { $0.date > $1.date },
                    group.value.filter(\.isSpending).map(\.amount).reduce(0, +)
                )
            }
            .sorted { $0.0 > $1.0 }
    }

    private let palette: [Color] = [
        .blue, .orange, .green, .purple, .pink, .teal, .red, .yellow, .indigo, .mint, .cyan, .brown,
    ]

    private func categoryColor(_ name: String) -> Color {
        guard let index = categoryTotals.firstIndex(where: { $0.name == name }) else { return .gray }
        return palette[index % palette.count]
    }

    private func fmt(_ value: Double) -> String { database.formattedAmount(value) }

    // MARK: Body

    var body: some View {
        Group {
            if searchText.isEmpty {
                dashboard
            } else {
                searchResults
            }
        }
        .alert("월 예산 설정", isPresented: $showingBudgetEditor) {
            TextField("예: 3000", text: $budgetInput)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Button("저장") {
                monthlyBudget = Double(budgetInput.replacingOccurrences(of: ",", with: "")) ?? 0
                budgetInput = ""
            }
            if monthlyBudget > 0 {
                Button("예산 해제", role: .destructive) { monthlyBudget = 0 }
            }
            Button("취소", role: .cancel) { budgetInput = "" }
        } message: {
            Text("한 달 지출 목표를 정하면 남은 예산과 사용률을 보여줘요.")
        }
        .sheet(isPresented: $showingBalanceEditor) {
            BalanceEditorView(database: database)
        }
    }

    private var dashboard: some View {
        List {
            if !unreviewed.isEmpty {
                Section {
                    NavigationLink {
                        ReviewQueueView(database: database)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "tray.full")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("메일에서 가져온 거래 \(unreviewed.count)건")
                                    .font(.subheadline.weight(.medium))
                                Text("카테고리를 확인하고 확정해 주세요")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listRowBackground(Rectangle().fill(.ultraThinMaterial))
            }

            Section {
                monthHeader
                balanceRow
                heroSummary
                budgetRow
            }
            .listRowBackground(Rectangle().fill(.ultraThinMaterial))

            if dailyTotals.count > 1 {
                Section {
                    dailyChart
                }
                .listRowBackground(Rectangle().fill(.ultraThinMaterial))
            }

            if trend.contains(where: { $0.total > 0 }) {
                Section {
                    trendChart
                }
                .listRowBackground(Rectangle().fill(.ultraThinMaterial))
            }

            if !categoryTotals.isEmpty {
                Section {
                    categoryChart
                    categoryBars
                }
                .listRowBackground(Rectangle().fill(.ultraThinMaterial))
            }

            if !monthItems.isEmpty {
                Section {
                    insightsGrid
                }
                .listRowBackground(Rectangle().fill(.ultraThinMaterial))
            }

            if dayGroups.isEmpty {
                Section {
                    Text("이 달에는 기록이 없어요")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
                .listRowBackground(Rectangle().fill(.ultraThinMaterial))
            }

            ForEach(dayGroups, id: \.day) { group in
                Section {
                    ForEach(group.items) { item in
                        entryRow(item)
                    }
                } header: {
                    HStack {
                        Text(group.day.formatted(.dateTime.month().day().weekday(.wide)))
                        Spacer()
                        Text(fmt(group.total))
                    }
                }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #else
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
    }

    // MARK: Month navigation

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)

            Spacer()

            VStack(spacing: 2) {
                Text(monthAnchor.formatted(.dateTime.year().month(.wide)))
                    .font(.headline)
                if !isCurrentMonth {
                    Button("오늘로") { monthAnchor = .now }
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
            }

            Spacer()

            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private func shiftMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = next
        }
    }

    // MARK: Hero summary

    private var heroSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isCurrentMonth ? "이번 달 지출" : "지출 합계")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(fmt(monthTotal))
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if let delta = deltaPercent {
                    deltaChip(delta)
                }
            }

            if let delta = deltaPercent {
                Text(delta >= 0
                     ? "지난달 같은 기간보다 \(fmt(abs(monthTotal - previousSamePeriodTotal))) 더 썼어요"
                     : "지난달 같은 기간보다 \(fmt(abs(monthTotal - previousSamePeriodTotal))) 아꼈어요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("지난달 기록이 없어요")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 0) {
                statBlock("일평균", fmt(dailyAverage))
                if let projected = projectedTotal {
                    statBlock("월말 예상", fmt(projected))
                }
                if monthIncome > 0 {
                    statBlock("수입", fmt(monthIncome))
                }
                statBlock("거래", "\(monthItems.count)건")
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 6)
    }

    private func deltaChip(_ delta: Double) -> some View {
        let up = delta >= 0
        return HStack(spacing: 3) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                .font(.caption2.bold())
            Text("\(abs(delta).formatted(.number.precision(.fractionLength(0))))%")
                .font(.caption.bold())
                .monospacedDigit()
        }
        .foregroundStyle(up ? Color.red : Color.green)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((up ? Color.red : Color.green).opacity(0.12), in: Capsule())
    }

    private func statBlock(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Balance

    @ViewBuilder
    private var balanceRow: some View {
        if let balance {
            Button {
                showingBalanceEditor = true
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("남은 돈")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text("\(balance.anchoredAt.formatted(date: .abbreviated, time: .omitted)) 기준 · 이후 \(balance.appliedCount)건")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(fmt(balance.current))
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(balance.current < 0 ? Theme.negativeRed : Color.primary)
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)
        } else {
            Button {
                showingBalanceEditor = true
            } label: {
                Label("계좌 잔액 설정", systemImage: "banknote")
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: Budget progress

    @ViewBuilder
    private var budgetRow: some View {
        if monthlyBudget > 0 {
            let progress = min(monthTotal / monthlyBudget, 1.0)
            let over = monthTotal > monthlyBudget
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("예산")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(over
                         ? "\(fmt(monthTotal - monthlyBudget)) 초과"
                         : "\(fmt(monthlyBudget - monthTotal)) 남음")
                        .font(.caption.bold())
                        .foregroundStyle(over ? .orange : .secondary)
                        .monospacedDigit()
                }

                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.glassTrack)
                    GeometryReader { geo in
                        Capsule()
                            .fill(over ? AnyShapeStyle(Color.orange) : AnyShapeStyle(Theme.glassInk.opacity(0.75)))
                            .frame(width: geo.size.width * progress)
                            .animation(.spring(duration: 0.5), value: progress)
                    }
                }
                .frame(height: 5)

                Text("예산 \(fmt(monthlyBudget)) 중 \(Int((monthTotal / monthlyBudget * 100).rounded()))% 사용")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture { showingBudgetEditor = true }
        } else {
            Button {
                showingBudgetEditor = true
            } label: {
                Label("월 예산 설정", systemImage: "target")
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: Charts

    private var dailyChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("일별 지출")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Chart {
                ForEach(dailyTotals, id: \.day) { point in
                    BarMark(
                        x: .value("일", point.day, unit: .day),
                        y: .value("지출", point.total)
                    )
                    .foregroundStyle(Theme.glassInk.opacity(0.6))
                    .cornerRadius(2)
                }
                if dailyAverage > 0 {
                    RuleMark(y: .value("일평균", dailyAverage))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisValueLabel(format: .dateTime.day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: 110)
        }
        .padding(.vertical, 4)
    }

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("6개월 추이")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Chart {
                ForEach(trend, id: \.month) { point in
                    BarMark(
                        x: .value("월", point.month, unit: .month),
                        y: .value("지출", point.total)
                    )
                    .foregroundStyle(
                        calendar.isDate(point.month, equalTo: monthAnchor, toGranularity: .month)
                            ? AnyShapeStyle(Theme.glassInk.opacity(0.75))
                            : AnyShapeStyle(Theme.glassInk.opacity(0.25))
                    )
                    .cornerRadius(4)
                }
                if trendAverage > 0 {
                    RuleMark(y: .value("평균", trendAverage))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                        .annotation(position: .top, alignment: .trailing) {
                            Text("평균 \(fmt(trendAverage))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: 130)
        }
        .padding(.vertical, 4)
    }

    private var categoryChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("카테고리별")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Chart(categoryTotals, id: \.name) { item in
                SectorMark(
                    angle: .value("금액", item.total),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                .cornerRadius(4)
                .foregroundStyle(categoryColor(item.name))
            }
            .chartLegend(.hidden)
            .chartBackground { proxy in
                GeometryReader { geometry in
                    if let anchor = proxy.plotFrame {
                        let frame = geometry[anchor]
                        VStack(spacing: 2) {
                            Text("합계")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(fmt(monthTotal))
                                .font(.headline)
                        }
                        .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            .frame(height: 180)
        }
        .padding(.vertical, 4)
    }

    private var categoryBars: some View {
        ForEach(categoryTotals, id: \.name) { item in
            let fraction = monthTotal > 0 ? item.total / monthTotal : 0
            VStack(spacing: 5) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(categoryColor(item.name))
                        .frame(width: 8, height: 8)
                    Text(item.name)
                        .font(.subheadline)
                    Spacer()
                    Text("\((fraction * 100).formatted(.number.precision(.fractionLength(0))))%")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                    Text(fmt(item.total))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.glassTrack)
                    GeometryReader { geo in
                        Capsule()
                            .fill(categoryColor(item.name).opacity(0.75))
                            .frame(width: max(geo.size.width * fraction, 3))
                    }
                }
                .frame(height: 4)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: Insights

    private var insightsGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                insightCell(
                    "최대 지출",
                    biggestExpense.map { fmt($0.amount) } ?? "—",
                    biggestExpense?.entry.title.isEmpty == false ? biggestExpense!.entry.title : nil
                )
                insightCell(
                    "최다 지출처",
                    topMerchant?.name ?? "—",
                    topMerchant.map { fmt($0.total) }
                )
            }
            HStack(spacing: 12) {
                insightCell(
                    "건당 평균",
                    monthItems.isEmpty ? "—" : fmt(monthTotal / Double(monthItems.count)),
                    nil
                )
                insightCell(
                    "최다 카테고리",
                    categoryTotals.first?.name ?? "—",
                    categoryTotals.first.map { fmt($0.total) }
                )
            }
        }
        .padding(.vertical, 4)
    }

    private func insightCell(_ title: String, _ value: String, _ sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let sub {
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Rows

    private func entryRow(_ item: Item, showDate: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.entry.title.isEmpty ? "(제목 없음)" : item.entry.title)
                    .lineLimit(1)
                subtitle(for: item)
                if showDate {
                    Text(item.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text((EntryKind.sign(item.kind) > 0 ? "+" : "") + fmt(item.amount))
                .font(.body.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(EntryKind.sign(item.kind) > 0 ? Theme.incomeGreen : .primary)
        }
        .contentShape(Rectangle())
        .onTapGesture { editingEntry = item.entry }
        .swipeActions(edge: .trailing) {
            Button("삭제", role: .destructive) { delete(item.entry) }
        }
        .contextMenu {
            Button("편집") { editingEntry = item.entry }
            Button("삭제", role: .destructive) { delete(item.entry) }
        }
        .listRowBackground(Rectangle().fill(.ultraThinMaterial))
    }

    @ViewBuilder
    private func subtitle(for item: Item) -> some View {
        let needsReview = database.reviewedProperty.map {
            item.entry.sourceKind == "email" && !item.entry.bool(for: $0)
        } ?? false
        let parts = [
            item.kind == EntryKind.expense ? item.category : item.kind,
            database.methodProperty.flatMap { item.entry.text(for: $0) } ?? "",
            needsReview ? "검토 대기" : "",
        ].filter { !$0.isEmpty }
        if !parts.isEmpty {
            HStack(spacing: 5) {
                Circle()
                    .fill(categoryColor(item.category))
                    .frame(width: 6, height: 6)
                Text(parts.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: Search results (flat, all months)

    private var searchResults: some View {
        let query = searchText.lowercased()
        let results = everyItem
            .filter { item in
                item.entry.title.lowercased().contains(query)
                    || item.category.lowercased().contains(query)
                    || (item.entry.values ?? []).contains { $0.textValue?.lowercased().contains(query) == true }
            }
            .sorted { $0.date > $1.date }

        return Group {
            if results.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    // entryRow must BE the row, not be wrapped in one: swipe
                    // actions and row backgrounds only apply at the top level.
                    ForEach(results) { item in
                        entryRow(item, showDate: true)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: Actions

    private func delete(_ entry: POSEntry) {
        NotionSyncService.shared.entryWillDelete(entry)
        context.delete(entry)
        try? context.save()
    }
}
