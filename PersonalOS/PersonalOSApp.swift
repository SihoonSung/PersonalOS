import SwiftUI
import SwiftData

@main
struct PersonalOSApp: App {
    let container: ModelContainer = {
        let schema = Schema([
            TodoItem.self,
            BudgetEntry.self,
            Investment.self,
            Goal.self
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none  // 추후 .automatic으로 변경하면 CloudKit 동기화 활성화
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("PersonalOS: ModelContainer 초기화 실패 — \(error)")
        }
    }()

    @State private var aiAvailability = AIAvailabilityManager()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .modelContainer(container)
                .environment(aiAvailability)
        }
    }
}
