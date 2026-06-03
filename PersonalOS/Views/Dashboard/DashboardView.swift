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
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacingM) {
                    // 헤더
                    VStack(alignment: .leading, spacing: Theme.spacingXS) {
                        Text(dateString)
                            .font(Theme.caption())
                            .foregroundStyle(.secondary)
                        Text(greeting)
                            .font(Theme.largeTitle())
                    }
                    .padding(.horizontal, Theme.spacingM)

                    // AI 사용 불가 배너
                    if !aiAvailability.isAvailable && !aiAvailability.unavailableReason.isEmpty {
                        AIUnavailableBanner(message: aiAvailability.unavailableReason)
                            .padding(.horizontal, Theme.spacingM)
                    }

                    // 할 일 카드
                    TaskSummaryCard()
                        .padding(.horizontal, Theme.spacingM)

                    // 캘린더 카드
                    CalendarCard()
                        .padding(.horizontal, Theme.spacingM)

                    // 가계부 카드
                    BudgetSummaryCard()
                        .padding(.horizontal, Theme.spacingM)

                    // 투자 요약 카드
                    InvestmentSummaryCard()
                        .padding(.horizontal, Theme.spacingM)

                    // 오늘 마감 할 일 미리보기
                    TodayTaskPreview()
                        .padding(.horizontal, Theme.spacingM)

                    // AI 비서 카드
                    AIAssistantCard(onTap: { showAIAssistant = true })
                        .padding(.horizontal, Theme.spacingM)

                    Spacer(minLength: 100)
                }
                .padding(.vertical, Theme.spacingM)
            }
            .navigationBarHidden(true)
            .overlay(alignment: .bottom) {
                QuickAddBar()
                    .padding(.bottom, Theme.spacingM)
                    .background(.ultraThinMaterial)
            }
        }
        .sheet(isPresented: $showAIAssistant) {
            AIAssistantView()
                .presentationDetents([.large])
        }
    }
}

// MARK: - 투자 요약 카드

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

    private var hasQuotes: Bool { !quotes.isEmpty }

    var body: some View {
        if investments.isEmpty { EmptyView() } else {
            VStack(alignment: .leading, spacing: Theme.spacingS) {
                Label(L.investmentCardTitle, systemImage: "chart.line.uptrend.xyaxis")
                    .font(Theme.caption().bold())
                    .foregroundStyle(.secondary)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hasQuotes ? totalValue.formattedUSD() : totalCost.formattedUSD())
                            .font(.title2.bold())
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                        Text(L.investmentTotalValue)
                            .font(Theme.caption2())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if hasQuotes {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%@$%.2f", totalPnL >= 0 ? "+" : "-", abs(totalPnL)))
                                .font(Theme.headline())
                                .foregroundStyle(totalPnL >= 0 ? Theme.positiveGreen : Theme.negativeRed)
                                .monospacedDigit()
                            Text(L.investmentPnL)
                                .font(Theme.caption2())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: Theme.spacingXS) {
                    ForEach(investments.prefix(4)) { inv in
                        Text(inv.ticker)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    if investments.count > 4 {
                        Text("+\(investments.count - 4)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
            .cardStyle()
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
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "sparkles")
                            .font(.system(size: 20))
                            .foregroundStyle(.blue)
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
            }
            .buttonStyle(.plain)
            .cardStyle()
        }
    }
}

// MARK: - 오늘 마감 할 일 미리보기

private struct TodayTaskPreview: View {
    @Query(
        filter: #Predicate<TodoItem> { !$0.isCompleted },
        sort: \TodoItem.dueDate
    )
    private var incompleteTasks: [TodoItem]

    private var todayTasks: [TodoItem] {
        incompleteTasks.filter { $0.isDueToday || $0.isOverdue }.prefix(3).map { $0 }
    }

    var body: some View {
        if !todayTasks.isEmpty {
            VStack(alignment: .leading, spacing: Theme.spacingS) {
                Text(L.focusNow)
                    .font(Theme.caption().bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.spacingXS)

                VStack(spacing: Theme.spacingXS) {
                    ForEach(todayTasks) { task in
                        HStack(spacing: Theme.spacingS) {
                            PriorityDot(priority: task.priority)
                            Text(task.title)
                                .font(Theme.body())
                                .lineLimit(1)
                            Spacer()
                            if task.isOverdue {
                                Text(L.overdueBadge)
                                    .font(Theme.caption2().bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red)
                                    .clipShape(Capsule())
                            } else if let d = task.dueDate {
                                Text(d.formatted(.dateTime.hour().minute()))
                                    .font(Theme.caption())
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .padding(Theme.spacingS)
                        .background(Theme.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusS))
                    }
                }
            }
        }
    }
}
