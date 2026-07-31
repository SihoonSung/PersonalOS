import SwiftUI
import SwiftData

@main
struct PersonalOSApp: App {

    let container: ModelContainer

    init() {
        let schema = Schema([POSDatabase.self, POSProperty.self, POSEntry.self, POSValue.self])

        // Try CloudKit-backed store first; fall back to local-only so the app
        // still runs before iCloud signing/capabilities are configured.
        do {
            let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            container = try ModelContainer(for: schema, configurations: [cloud])
        } catch {
            do {
                let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
                container = try ModelContainer(for: schema, configurations: [local])
            } catch {
                fatalError("ModelContainer 생성 실패: \(error)")
            }
        }

        Templates.seedIfNeeded(context: container.mainContext)

        NotionSyncService.shared.configure(container: container)
        NotionSyncService.shared.scheduleAutoSync(after: 5) // catch remote changes on launch

        #if os(macOS)
        MCPServer.shared.configure(container: container)
        if AppSettings.mcpEnabled {
            MCPServer.shared.start(port: AppSettings.mcpPort)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)

        #if os(macOS)
        Settings {
            SettingsView()
                .modelContainer(container)
        }
        #endif
    }
}
