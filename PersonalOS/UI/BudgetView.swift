import SwiftUI
import SwiftData
import Charts

// MARK: - Budget dashboard
//
// Month-scoped dashboard: total + vs-last-month, 6-month trend bar chart,
// category donut with legend, then entries grouped by day. Searching
// switches to a flat result list across all months.

struct BudgetView: View {
    @Environment(\.modelContext) private var context
    @Bindable var database: POSDatabase
    let searchText: String
    @Binding var editingEntry: POSEntry?

    @State private var monthAnchor: Date = .now

    private var calendar: Calendar { .current }

    // MARK: Resolved rows

    private struct Item: Identifiable {
        let entry: POSEntry
        let date: Date
        let amount: Double
        let category: String
        var id: UUID { entry.uuid }
    }

    private var allItems: [Item] {
        let dateProp = database.dateProperty
        let amountProp = database.amountProperty
        let categoryProp = database.categoryProperty
        return (database.entries ?? []).map { entry in
            Item(
                entry: entry,
                date: dateProp.flatMap { entry.date(for: $0) } ?? entry.createdAt,
                amount: amountProp.flatMap { entry.number(for: $0) } ?? 0,
                category: categoryProp.flatMap { entry.text(for: $0) } ?? "기타"
            )
        }
    }

    private var monthItems: [Item] {
        allItems.filter { calendar.isDate($0.date, equalTo: monthAnchor, toGranularity: .month) }
    }

    private var monthTotal: Double { monthItems.map(\.amount).reduce(0, +) }

    private var previousMonthTotal: Double {
        guard let prev = calendar.date(byAdding: .month, value: -1, to: monthAnchor) else { return 0 }
        return allItems
            .filter { calendar.isDate($0.date, equalTo: prev, toGranularity: .month) }
            .map(\.amount)
            .reduce(0, +)
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

    private var categoryTotals: [(name: String, total: Double)] {
        Dictionary(grouping: monthItems, by: \.category)
            .map { ($0.key, $0.value.map(\.amount).reduce(0, +)) }
            .sorted { $0.1 > $1.1 }
    }

    private var dayGroups: [(day: Date, items: [Item], total: Double)] {
        Dictionary(grouping: monthItems) { calendar.startOfDay(for: $0.date) }
            .map { ($0.key, $0.value.sorted { $0.date > $1.date }, $0.value.map(\.amount).reduce(0, +)) }
            .sorted { $0.0 > $1.0 }
    }

    private let palette: [Color] = [
        .blue, .orange, .green, .purple, .pink, .teal, .red, .yellow, .indigo, .mint, .cyan, .brown,
    ]

    private func categoryColor(_ name: String) -> Color {
        guard let index = categoryTotals.firstIndex(where: { $0.name == name }) else { return .gray }
        return palette[index % palette.count]
    }

    // MARK: Body

    var body: some View {
        if searchText.isEmpty {
            dashboard
        } else {
            searchResults
        }
    }

    private var dashboard: some View {
        List {
            Section {
                monthHeader
                summary
                if trend.contains(where: { $0.total > 0 }) {
                    trendChart
                }
                if !categoryTotals.isEmpty {
                    categoryChart
                    categoryLegend
                }
            }

            if dayGroups.isEmpty {
                Section {
                    Text("이 달에는 기록이 없어요")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
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
                        Text(database.formattedAmount(group.total))
                    }
                }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #else
        .listStyle(.insetGrouped)
        #endif
    }

    // MARK: Month navigation

    private var isCurrentMonth: Bool {
        calendar.isDate(monthAnchor, equalTo: .now, toGranularity: .month)
    }

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

    // MARK: Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("지출 합계")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(database.formattedAmount(monthTotal))
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .contentTransition(.numericText())
            comparisonLine
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var comparisonLine: some View {
        if previousMonthTotal > 0 {
            let diff = monthTotal - previousMonthTotal
            let percent = abs(diff) / previousMonthTotal * 100
            HStack(spacing: 4) {
                Image(systemName: diff > 0 ? "arrow.up.right" : "arrow.down.right")
                let percentText = percent.formatted(.number.precision(.fractionLength(0)))
                Text(diff > 0
                     ? "지난달보다 \(database.formattedAmount(abs(diff))) (\(percentText)%) 늘었어요"
                     : "지난달보다 \(database.formattedAmount(abs(diff))) (\(percentText)%) 줄었어요")
            }
            .font(.caption)
            .foregroundStyle(diff > 0 ? .red : .green)
        } else {
            Text("지난달 기록이 없어요")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Charts

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("월별 추이")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Chart(trend, id: \.month) { point in
                BarMark(
                    x: .value("월", point.month, unit: .month),
                    y: .value("지출", point.total)
                )
                .foregroundStyle(
                    calendar.isDate(point.month, equalTo: monthAnchor, toGranularity: .month)
                        ? AnyShapeStyle(Color.accentColor)
                        : AnyShapeStyle(Color.accentColor.opacity(0.35))
                )
                .cornerRadius(4)
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
                .font(.subheadline)
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
                            Text(database.formattedAmount(monthTotal))
                                .font(.headline)
                        }
                        .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            .frame(height: 190)
        }
        .padding(.vertical, 4)
    }

    private var categoryLegend: some View {
        ForEach(categoryTotals, id: \.name) { item in
            HStack(spacing: 10) {
                Circle()
                    .fill(categoryColor(item.name))
                    .frame(width: 9, height: 9)
                Text(item.name)
                Spacer()
                Text(database.formattedAmount(item.total))
                    .foregroundStyle(.secondary)
                Text("\((item.total / max(monthTotal, 1) * 100).formatted(.number.precision(.fractionLength(0))))%")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 38, alignment: .trailing)
            }
            .font(.subheadline)
        }
    }

    // MARK: Rows

    private func entryRow(_ item: Item) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.entry.title.isEmpty ? "(제목 없음)" : item.entry.title)
                    .lineLimit(1)
                subtitle(for: item)
            }
            Spacer()
            Text(database.formattedAmount(item.amount))
                .font(.body.weight(.medium))
                .monospacedDigit()
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
    }

    @ViewBuilder
    private func subtitle(for item: Item) -> some View {
        let parts = [
            item.category,
            database.orderedProperties.first { $0.name == "결제수단" }
                .flatMap { item.entry.text(for: $0) } ?? "",
        ].filter { !$0.isEmpty }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: Search results (flat, all months)

    private var searchResults: some View {
        let query = searchText.lowercased()
        let results = allItems
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
                    ForEach(results) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            entryRow(item)
                            Text(item.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
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
