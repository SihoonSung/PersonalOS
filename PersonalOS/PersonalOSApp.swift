import SwiftUI
import SwiftData

@main
@MainActor
struct PersonalOSApp: App {
    let container: ModelContainer = {
        let schema = Schema([
            TodoItem.self,
            BudgetEntry.self,
            RecurringEntry.self,
            Investment.self,
            Goal.self
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("PersonalOS: ModelContainer 초기화 실패 — \(error)")
        }
    }()

    @State private var aiAvailability = AIAvailabilityManager()
    @State private var calendarService = CalendarService()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .modelContainer(container)
                .environment(aiAvailability)
                .environment(calendarService)
                .onAppear {
                    RecurringService.applyIfNeeded(context: container.mainContext)
                    setupCalendarSync()
                }
        }
    }

    // MARK: - 캘린더 ↔ 앱 양방향 동기화 설정

    @MainActor
    private func setupCalendarSync() {
        let context = container.mainContext

        // 1. 앱이 추적 중인 식별자 목록을 CalendarService에 주입
        refreshTrackedIdentifiers()

        // 2. 캘린더 외부 삭제 감지 → 앱에서 해당 TodoItem 처리
        calendarService.onExternalDeletion = { deletedIdentifiers in
            Task { @MainActor in
                handleExternalDeletion(identifiers: deletedIdentifiers, context: context)
            }
        }
    }

    @MainActor
    private func refreshTrackedIdentifiers() {
        let context = container.mainContext
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate { $0.calendarEventIdentifier != nil }
        )
        let todos = (try? context.fetch(descriptor)) ?? []
        calendarService.trackedIdentifiers = Set(todos.compactMap { $0.calendarEventIdentifier })
    }

    @MainActor
    private func handleExternalDeletion(identifiers: [String], context: ModelContext) {
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate { $0.calendarEventIdentifier != nil }
        )
        guard let todos = try? context.fetch(descriptor) else { return }

        let identifierSet = Set(identifiers)
        var changed = false

        for todo in todos {
            guard let id = todo.calendarEventIdentifier,
                  identifierSet.contains(id) else { continue }

            // 캘린더에서 삭제됐으면 앱에서도 calendarEventIdentifier 제거
            // (할 일 자체는 삭제하지 않음 — 사용자가 캘린더에서만 지운 것일 수 있음)
            todo.calendarEventIdentifier = nil
            changed = true
        }

        if changed {
            try? context.save()
            // 식별자 목록 갱신
            refreshTrackedIdentifiers()
        }
    }
}
