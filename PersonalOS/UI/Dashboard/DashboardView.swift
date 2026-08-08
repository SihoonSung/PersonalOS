import SwiftUI
import SwiftData

/// Liquid Glass 홈 대시보드 — 앱의 루트 화면.
/// 좌상단: 데이터베이스 목록, 우상단: 설정. 카드 chevron으로 개별 DB 이동.
struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \POSDatabase.sortIndex) private var databases: [POSDatabase]
    var openDatabase: (POSDatabase) -> Void = { _ in }
    var onOpenDatabases: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onOpenRecurring: (POSDatabase) -> Void = { _ in }
    var onOpenWorkout: () -> Void = {}

    private var todoDatabase: POSDatabase? {
        databases.first { $0.templateKey == TemplateKey.todo }
            ?? databases.first { $0.doneProperty != nil }
    }

    private var budgetDatabase: POSDatabase? {
        databases.first { $0.templateKey == TemplateKey.budget }
    }

    /// 할 일/가계부를 제외한 나머지 — 템플릿별 전용 카드 or 제네릭 카드.
    private var extraDatabases: [POSDatabase] {
        databases.filter { db in
            db.uuid != todoDatabase?.uuid && db.uuid != budgetDatabase?.uuid
        }
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

    @ViewBuilder
    private func extraCard(_ db: POSDatabase) -> some View {
        switch db.templateKey {
        case TemplateKey.bodyLog:
            BodyLogCard(database: db, onOpen: { openDatabase(db) })
        case TemplateKey.workout:
            WorkoutCard(database: db, onOpen: { openDatabase(db) })
        case TemplateKey.sermon:
            SermonCard(database: db, onOpen: { openDatabase(db) })
        case TemplateKey.expressions:
            ExpressionsCard(database: db, onOpen: { openDatabase(db) })
        default:
            GenericDatabaseCard(database: db, onOpen: { openDatabase(db) })
        }
    }

    var body: some View {
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

                // 문제가 있을 때만 나타난다 (정상이면 EmptyView).
                NotionStatusCard()

                if let todo = todoDatabase {
                    TodayFocusCard(database: todo, onOpen: { openDatabase(todo) })
                }

                if let budget = budgetDatabase {
                    BalanceCard(database: budget, onOpen: { openDatabase(budget) })

                    HStack(alignment: .top, spacing: Theme.spacingM) {
                        BudgetSummaryCard(database: budget, onOpen: { openDatabase(budget) })
                        TodaySpendCard(database: budget)
                    }

                    FixedCostCard(database: budget, onOpen: { onOpenRecurring(budget) })
                }

                CalendarCard()

                WorkoutReadyCard(onOpen: onOpenWorkout)

                if !extraDatabases.isEmpty {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: Theme.spacingM, alignment: .top),
                            GridItem(.flexible(), alignment: .top),
                        ],
                        spacing: Theme.spacingM
                    ) {
                        ForEach(extraDatabases) { db in
                            extraCard(db)
                        }
                    }
                }

                Spacer(minLength: 110)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.spacingM)
            .padding(.vertical, Theme.spacingM)
        }
        .scrollIndicators(.hidden)
        // 배경은 .background로: 블롭 Circle(460pt)이 화면보다 넓어도
        // 레이아웃 폭에 영향을 주지 않는다 (ZStack sibling이면 전체가 벌어짐)
        .background(DashboardBackground())
        .overlay(alignment: .bottom) {
            if let todo = todoDatabase {
                QuickAddBar(database: todo, style: .glass)
                    .padding(.horizontal, Theme.spacingM)
                    .padding(.bottom, Theme.spacingM)
            }
        }
        .onAppear { WidgetDataWriter.refresh(context: context) }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: onOpenDatabases) {
                    Label("데이터베이스", systemImage: "square.grid.2x2")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: onOpenSettings) {
                    Label("설정", systemImage: "gearshape")
                }
            }
        }
    }
}
