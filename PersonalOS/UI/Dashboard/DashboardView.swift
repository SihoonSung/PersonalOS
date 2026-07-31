import SwiftUI
import SwiftData

/// Liquid Glass 홈 대시보드 — 오늘 할 일 메인, 예산/오늘 지출 반폭 2열.
/// 템플릿 키(todo/budget)로 대상 데이터베이스를 찾으므로 이름을 바꿔도 동작.
struct DashboardView: View {
    @Query(sort: \POSDatabase.sortIndex) private var databases: [POSDatabase]
    var openDatabase: (POSDatabase) -> Void = { _ in }

    private var todoDatabase: POSDatabase? {
        databases.first { $0.templateKey == TemplateKey.todo }
            ?? databases.first { $0.doneProperty != nil }
    }

    private var budgetDatabase: POSDatabase? {
        databases.first { $0.templateKey == TemplateKey.budget }
    }

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
        ZStack {
            DashboardBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacingM) {
                        VStack(alignment: .leading, spacing: Theme.spacingXS) {
                            Text(dateString)
                                .font(Theme.caption().bold())
                                .foregroundStyle(.secondary)
                            Text(greeting)
                                .font(Theme.largeTitle())
                        }
                        .padding(.top, Theme.spacingS)

                        if let todo = todoDatabase {
                            TodayFocusCard(database: todo, onOpen: { openDatabase(todo) })
                        }

                        if let budget = budgetDatabase {
                            HStack(alignment: .top, spacing: Theme.spacingM) {
                                BudgetSummaryCard(database: budget, onOpen: { openDatabase(budget) })
                                TodaySpendCard(database: budget)
                            }
                        }

                    Spacer(minLength: 110)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.spacingM)
                .padding(.vertical, Theme.spacingM)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .bottom) {
            if let todo = todoDatabase {
                QuickAddBar(database: todo, style: .glass)
                    .padding(.horizontal, Theme.spacingM)
                    .padding(.bottom, Theme.spacingM)
            }
        }
    }
}
