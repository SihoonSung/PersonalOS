import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(AIAvailabilityManager.self) private var aiAvailability

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date.now)
        switch hour {
        case 5..<12: return "좋은 아침이에요"
        case 12..<17: return "좋은 오후예요"
        case 17..<21: return "좋은 저녁이에요"
        default: return "늦은 시간이네요"
        }
    }

    private var dateString: String {
        Date.now.formatted(.dateTime.year().month().day().weekday(.wide).locale(Locale(identifier: "ko_KR")))
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

                    // 가계부 카드
                    BudgetSummaryCard()
                        .padding(.horizontal, Theme.spacingM)

                    // 오늘 마감 할 일 미리보기
                    TodayTaskPreview()
                        .padding(.horizontal, Theme.spacingM)

                    Spacer(minLength: 100) // QuickAddBar 공간 확보
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
                Text("지금 집중할 일")
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
                                Text("연체")
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
