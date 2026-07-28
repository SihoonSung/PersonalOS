import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(AIAvailabilityManager.self) private var aiAvailability
    @State private var showAIAssistant = false

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date.now)
        switch hour {
        case 5..<12: return L.greetingMorning
        case 12..<17: return L.greetingAfternoon
        case 17..<21: return L.greetingEvening
        default: return L.greetingNight
        }
    }

    private var dateString: String {
        Date.now.formatted(.dateTime.year().month().day().weekday(.wide).locale(L.locale))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DashboardBackground()

                ScrollView {
                    GlassEffectContainer(spacing: 24) {
                        VStack(alignment: .leading, spacing: Theme.spacingM) {
                            // 헤더
                            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                                Text(dateString)
                                    .font(Theme.caption().bold())
                                    .foregroundStyle(.secondary)
                                Text(greeting)
                                    .font(Theme.largeTitle())
                            }
                            .padding(.top, Theme.spacingS)

                            // AI 사용 불가 배너
                            if !aiAvailability.isAvailable && !aiAvailability.unavailableReason.isEmpty {
                                AIUnavailableBanner(message: aiAvailability.unavailableReason)
                            }

                            // 오늘 할 일 — 메인 카드
                            TodayFocusCard()

                            // 예산 + 투자 — 반폭 글래스 카드
                            HStack(alignment: .top, spacing: Theme.spacingM) {
                                BudgetSummaryCard()
                                InvestmentSummaryCard()
                            }

                            // 오늘 일정
                            CalendarCard()

                            // AI 비서
                            AIAssistantCard(onTap: { showAIAssistant = true })

                            Spacer(minLength: 110)
                        }
                        .padding(.horizontal, Theme.spacingM)
                        .padding(.vertical, Theme.spacingM)
                    }
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarHidden(true)
            .overlay(alignment: .bottom) {
                QuickAddBar()
                    .padding(.bottom, Theme.spacingM)
            }
        }
        .sheet(isPresented: $showAIAssistant) {
            AIAssistantView()
                .presentationDetents([.large])
        }
    }
}

// MARK: - 투자 요약 카드 (컴팩트 글래스)

private struct InvestmentSummaryCard: View {
    @Query private var investments: [Investment]
    @State private var quotes: [String: QuoteResult] = [:]
    private let service = StockPriceService()

    private var totalValue: Double {
        investments.reduce(0) { $0 + $1.currentValue(currentPrice: quotes[$1.ticker]?.currentPrice ?? 0) }
    }

    private var totalCost: Double {
        investments.reduce(0) { $0 + $1.totalCost }
    }

    private var totalPnL: Double { totalValue - totalCost }

    private var pnlPercent: Double {
        guard totalCost > 0 else { return 0 }
        return totalPnL / totalCost * 100
    }

    private var hasQuotes: Bool { !quotes.isEmpty }

    var body: some View {
        if investments.isEmpty { EmptyView() } else {
            VStack(alignment: .leading, spacing: Theme.spacingS) {
                Text(L.investmentCardTitle)
                    .font(Theme.caption().bold())
                    .foregroundStyle(.secondary)

                Text(hasQuotes ? totalValue.formattedUSD() : totalCost.formattedUSD())
                    .font(.title3.bold())
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if hasQuotes {
                    Text(String(
                        format: "%@$%.2f (%@%.1f%%)",
                        totalPnL >= 0 ? "+" : "-", abs(totalPnL),
                        totalPnL >= 0 ? "+" : "-", abs(pnlPercent)
                    ))
                    .font(Theme.caption2().bold())
                    .foregroundStyle(totalPnL >= 0 ? Theme.positiveGreen : Theme.negativeRed)
                    .monospacedDigit()
                } else {
                    Text(L.investmentTotalCost)
                        .font(Theme.caption2())
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: Theme.spacingXS) {
                    ForEach(investments.prefix(3)) { inv in
                        Text(inv.ticker)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.glassTrack, in: Capsule())
                    }
                    if investments.count > 3 {
                        Text("+\(investments.count - 3)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCardStyle()
            .task { await fetchPrices() }
        }
    }

    private func fetchPrices() async {
        guard !investments.isEmpty else { return }
        let tickers = investments.map { $0.ticker }
        quotes = await service.fetchMultiple(tickers: tickers)
    }
}

// MARK: - AI 비서 카드

private struct AIAssistantCard: View {
    @Environment(AIAvailabilityManager.self) private var aiAvailability
    let onTap: () -> Void

    var body: some View {
        if aiAvailability.isAvailable {
            Button(action: onTap) {
                HStack(spacing: Theme.spacingM) {
                    ZStack {
                        Circle()
                            .fill(Theme.glassTrack)
                            .frame(width: 44, height: 44)
                        Image(systemName: "sparkles")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.aiAssistantCardTitle)
                            .font(Theme.body().bold())
                            .foregroundStyle(.primary)
                        Text(L.aiAssistantCardHint)
                            .font(Theme.caption())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .glassCardStyle(interactive: true)
        }
    }
}
