import SwiftUI
import SwiftData

struct InvestmentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Investment.createdAt) private var investments: [Investment]

    @State private var quotes: [String: QuoteResult] = [:]
    @State private var isLoading = false
    @State private var showAddSheet = false
    @State private var selectedInvestment: Investment?

    private let service = StockPriceService()

    private var totalValue: Double {
        investments.reduce(0) { $0 + ($1.currentValue(currentPrice: quotes[$1.ticker]?.currentPrice ?? 0)) }
    }

    private var totalCost: Double {
        investments.reduce(0) { $0 + $1.totalCost }
    }

    private var totalPnL: Double { totalValue - totalCost }

    private var totalPnLPercent: Double {
        guard totalCost > 0 else { return 0 }
        return (totalPnL / totalCost) * 100
    }

    var body: some View {
        Group {
            if investments.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: Theme.spacingM) {
                        summaryCard
                        positionsList
                        disclaimerText
                    }
                    .padding(Theme.spacingM)
                }
                .background(Theme.groupedBackground)
                .refreshable { await fetchPrices() }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
            }
            if !investments.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await fetchPrices() } } label: {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(isLoading ? 360 : 0))
                            .animation(
                                isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                                value: isLoading
                            )
                    }
                    .disabled(isLoading)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddInvestmentSheet()
                .presentationDetents([.medium])
                .onDisappear { Task { await fetchPrices() } }
        }
        .sheet(item: $selectedInvestment) { inv in
            AddInvestmentSheet(editing: inv)
                .presentationDetents([.medium])
                .onDisappear { Task { await fetchPrices() } }
        }
        .task { await fetchPrices() }
    }

    // MARK: - 요약 카드

    private var summaryCard: some View {
        VStack(spacing: Theme.spacingS) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isLoading ? L.investmentLoading : totalValue.formattedUSD())
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .redacted(reason: isLoading ? .placeholder : [])
                    Text(L.investmentTotalValue)
                        .font(Theme.caption2())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(pnlText)
                        .font(Theme.headline())
                        .foregroundStyle(totalPnL >= 0 ? Theme.positiveGreen : Theme.negativeRed)
                        .monospacedDigit()
                        .redacted(reason: isLoading ? .placeholder : [])
                    Text(L.investmentPnL)
                        .font(Theme.caption2())
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                SummaryPill(label: L.investmentTotalCost, value: totalCost.formattedUSD())
                Spacer()
                if totalPnLPercent != 0 {
                    Text(String(format: "%+.2f%%", totalPnLPercent))
                        .font(Theme.caption().bold())
                        .foregroundStyle(totalPnLPercent >= 0 ? Theme.positiveGreen : Theme.negativeRed)
                        .monospacedDigit()
                }
            }
        }
        .cardStyle()
        .redacted(reason: isLoading ? .placeholder : [])
    }

    private var pnlText: String {
        String(format: "%@$%.2f", totalPnL >= 0 ? "+" : "-", abs(totalPnL))
    }

    // MARK: - 종목 리스트

    private var positionsList: some View {
        List {
            ForEach(investments) { inv in
                InvestmentRowView(
                    investment: inv,
                    quote: quotes[inv.ticker]
                )
                .contentShape(Rectangle())
                .onTapGesture { selectedInvestment = inv }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        context.delete(inv)
                        try? context.save()
                        quotes.removeValue(forKey: inv.ticker)
                    } label: {
                        Label(L.investmentSwipeDelete, systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var disclaimerText: some View {
        Text(L.investmentDisclaimer)
            .font(Theme.caption2())
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.spacingM)
    }

    // MARK: - 빈 상태

    private var emptyState: some View {
        VStack(spacing: Theme.spacingM) {
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text(L.investmentEmptyTitle)
                .font(Theme.headline())
            Text(L.investmentEmptyHint)
                .font(Theme.body())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L.investmentAddButton) { showAddSheet = true }
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding(Theme.spacingXL)
    }

    // MARK: - 시세 조회

    private func fetchPrices() async {
        guard !investments.isEmpty else { return }
        isLoading = true
        let tickers = investments.map { $0.ticker }
        let results = await service.fetchMultiple(tickers: tickers)
        quotes = results
        isLoading = false
    }
}

// MARK: - 종목 행

struct InvestmentRowView: View {
    let investment: Investment
    let quote: QuoteResult?

    private var currentPrice: Double { quote?.currentPrice ?? 0 }
    private var pnl: Double { investment.unrealizedPnL(currentPrice: currentPrice) }
    private var pnlPercent: Double { investment.unrealizedPnLPercent(currentPrice: currentPrice) }
    private var dayChange: Double { quote?.dayChangePercent ?? 0 }
    private var hasPrice: Bool { quote != nil }

    var body: some View {
        HStack(spacing: Theme.spacingM) {
            // 티커 배지
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusS)
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 48, height: 48)
                Text(investment.ticker.prefix(4))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.blue)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(investment.name.isEmpty ? investment.ticker : investment.name)
                    .font(Theme.body())
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(String(format: "%.4g주", investment.shares))
                        .font(Theme.caption2())
                        .foregroundStyle(.secondary)
                    if hasPrice {
                        Text("·")
                            .font(Theme.caption2())
                            .foregroundStyle(.secondary)
                        Text(String(format: "%+.2f%%", dayChange))
                            .font(Theme.caption2().bold())
                            .foregroundStyle(dayChange >= 0 ? Theme.positiveGreen : Theme.negativeRed)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if hasPrice {
                    Text(investment.currentValue(currentPrice: currentPrice).formattedUSD())
                        .font(Theme.body().monospacedDigit())
                        .foregroundStyle(.primary)
                    Text(String(format: "%+.2f%%", pnlPercent))
                        .font(Theme.caption2().bold())
                        .foregroundStyle(pnl >= 0 ? Theme.positiveGreen : Theme.negativeRed)
                        .monospacedDigit()
                } else {
                    Text(investment.totalCost.formattedUSD())
                        .font(Theme.body().monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("—")
                        .font(Theme.caption2())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(Theme.spacingM)
    }
}

// MARK: - 작은 요약 pill

private struct SummaryPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.caption2())
                .foregroundStyle(.secondary)
            Text(value)
                .font(Theme.caption().bold())
                .monospacedDigit()
        }
    }
}
