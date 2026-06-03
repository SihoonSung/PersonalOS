import SwiftUI
import SwiftData
import Combine

struct AIAssistantView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AIAvailabilityManager.self) private var aiAvailability
    @Environment(\.modelContext) private var context

    @State private var viewModel = AIAssistantViewModel()
    @AppStorage("defaultCurrency") private var defaultCurrency: String = Currency.krw.rawValue

    var body: some View {
        NavigationStack {
            Group {
                if aiAvailability.isAvailable {
                    chatView
                } else {
                    unavailableView
                }
            }
            .navigationTitle(L.aiAssistantNavTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.taskDetailDone) { dismiss() }
                        .bold()
                }
            }
        }
        .task {
            guard aiAvailability.isAvailable else { return }
            let summary = buildContextSummary()
            viewModel.startSession(contextSummary: summary)
        }
    }

    // MARK: - 채팅 화면

    private var chatView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Theme.spacingS) {
                        // 웰컴 메시지
                        if viewModel.messages.isEmpty && !viewModel.isResponding {
                            WelcomeBubble()
                                .padding(.top, Theme.spacingM)
                        }

                        ForEach(viewModel.messages) { msg in
                            ChatBubble(message: msg)
                                .id(msg.id)
                        }

                        if viewModel.isResponding {
                            if viewModel.streamingText.isEmpty {
                                TypingIndicator()
                            } else {
                                ChatBubble(message: ChatMessage(
                                    role: .assistant,
                                    content: viewModel.streamingText
                                ))
                            }
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(Theme.spacingM)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom") }
                }
                .onChange(of: viewModel.streamingText) { _, _ in
                    proxy.scrollTo("bottom")
                }
            }

            Divider()
            inputBar
        }
    }

    private var inputBar: some View {
        HStack(spacing: Theme.spacingS) {
            TextField(L.aiAssistantPlaceholder, text: Bindable(viewModel).inputText, axis: .vertical)
                .font(Theme.body())
                .lineLimit(1...4)
                .padding(.horizontal, Theme.spacingS)
                .padding(.vertical, 10)
                .background(Theme.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusL))
                .onSubmit {
                    guard !viewModel.isResponding else { return }
                    Task { await viewModel.send() }
                }

            Button {
                Task { await viewModel.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isResponding ? Color.secondary : Color.blue)
            }
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isResponding)
        }
        .padding(Theme.spacingM)
        .background(Theme.background)
    }

    // MARK: - 미지원 화면

    private var unavailableView: some View {
        VStack(spacing: Theme.spacingM) {
            Spacer()
            Image(systemName: "cpu")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text(L.aiAssistantUnavailable)
                .font(Theme.body())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.spacingXL)
            if !aiAvailability.unavailableReason.isEmpty {
                Text(aiAvailability.unavailableReason)
                    .font(Theme.caption())
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.spacingXL)
            }
            Spacer()
        }
    }

    // MARK: - 컨텍스트 요약 생성

    private func buildContextSummary() -> String {
        let cal = Calendar.current
        let now = Date.now

        // 할 일 요약
        let taskDescriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate { !$0.isCompleted }
        )
        let tasks = (try? context.fetch(taskDescriptor)) ?? []
        let overdue = tasks.filter { $0.isOverdue }.count
        let todayTasks = tasks.filter { $0.isDueToday }.count

        // 이번 달 가계부 요약
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) ?? now
        let expenseType = EntryType.expense.rawValue
        let incomeType = EntryType.income.rawValue
        var expenseDesc = FetchDescriptor<BudgetEntry>(
            predicate: #Predicate {
                $0.type == expenseType && $0.currency == defaultCurrency &&
                $0.date >= monthStart && $0.date < monthEnd
            }
        )
        expenseDesc.propertiesToFetch = [\.amount]
        var incomeDesc = FetchDescriptor<BudgetEntry>(
            predicate: #Predicate {
                $0.type == incomeType && $0.currency == defaultCurrency &&
                $0.date >= monthStart && $0.date < monthEnd
            }
        )
        incomeDesc.propertiesToFetch = [\.amount]
        let monthExpense = ((try? context.fetch(expenseDesc)) ?? []).reduce(0) { $0 + $1.amount }
        let monthIncome = ((try? context.fetch(incomeDesc)) ?? []).reduce(0) { $0 + $1.amount }

        // 투자 요약
        let investments = (try? context.fetch(FetchDescriptor<Investment>())) ?? []

        // 목표 요약
        let activeGoals = (try? context.fetch(FetchDescriptor<Goal>(
            predicate: #Predicate { !$0.isCompleted }
        ))) ?? []

        let currency = Currency(rawValue: defaultCurrency) ?? .krw
        let monthStr = now.formatted(.dateTime.year().month().locale(L.locale))

        let carryover: Double = {
            let allDesc = FetchDescriptor<BudgetEntry>()
            let all = (try? context.fetch(allDesc)) ?? []
            return all.filter { $0.currency == defaultCurrency && $0.date < monthStart }
                      .reduce(0) { $0 + ($1.isExpense ? -$1.amount : $1.amount) }
        }()
        let totalBalance = carryover + monthIncome - monthExpense

        return """
        오늘 날짜: \(currentLocalISODateString())

        [할 일 현황]
        - 미완료 할 일: \(tasks.count)개
        - 오늘 마감: \(todayTasks)개
        - 기한 초과(연체): \(overdue)개

        [\(monthStr) 가계부]
        - 이번 달 지출(쓴 돈): \(currency.format(monthExpense))
        - 이번 달 수입(들어온 돈): \(currency.format(monthIncome))
        - 이번 달 순손익(수입-지출): \(currency.format(monthIncome - monthExpense))
        - 이월(전달까지 누적 잔액): \(currency.format(carryover))
        - 앱 기준 총 보유(이월+이번달 순): \(currency.format(totalBalance))
        ※ 실제 은행 계좌 잔액은 알 수 없음

        [투자 포트폴리오]
        - 보유 종목 수: \(investments.count)개
        \(investments.isEmpty ? "  (없음)" : investments.map { "  · \($0.ticker) \(String(format: "%.4g", $0.shares))주, 평균단가 \(String(format: "%.2f", $0.averageCost)) \($0.currency)" }.joined(separator: "\n"))
        ※ 현재 시세는 실시간 조회 필요, 이 요약에는 없음

        [진행 중인 목표]
        - 활성 목표 수: \(activeGoals.count)개
        \(activeGoals.isEmpty ? "  (없음)" : activeGoals.map { "  · \($0.title): \($0.progressPercent)% 달성 (\(Int($0.currentValue))/\(Int($0.targetValue))\($0.unit.isEmpty ? "" : " \($0.unit)"))" }.joined(separator: "\n"))
        """
    }
}

// MARK: - 채팅 버블

private struct ChatBubble: View {
    let message: ChatMessage

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            Text(message.content)
                .font(Theme.body())
                .foregroundStyle(isUser ? .white : .primary)
                .padding(.horizontal, Theme.spacingM)
                .padding(.vertical, Theme.spacingS)
                .background(isUser ? Color.blue : Theme.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusL))

            if !isUser { Spacer(minLength: 60) }
        }
    }
}

private struct WelcomeBubble: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            HStack {
                Text(L.aiAssistantWelcome)
                    .font(Theme.body())
                    .foregroundStyle(.primary)
                    .padding(.horizontal, Theme.spacingM)
                    .padding(.vertical, Theme.spacingS)
                    .background(Theme.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusL))
                Spacer(minLength: 60)
            }

            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 11))
                Text(L.aiAssistantDisclaimer)
                    .font(.system(size: 11))
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
        }
    }
}

private struct TypingIndicator: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 7, height: 7)
                        .opacity(phase == i ? 1.0 : 0.3)
                }
            }
            .padding(.horizontal, Theme.spacingM)
            .padding(.vertical, Theme.spacingS)
            .background(Theme.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusL))
            Spacer()
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}
