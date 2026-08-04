import SwiftUI
import SwiftData
#if canImport(BackgroundTasks) && os(iOS)
import BackgroundTasks
#endif

@main
struct PersonalOSApp: App {

    let container: ModelContainer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let schema = Schema([
            POSDatabase.self,
            POSProperty.self,
            POSEntry.self,
            POSValue.self,
            POSMerchantRule.self,
            POSBalanceAnchor.self,
        ])

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
        Templates.migrate(context: container.mainContext)

        MailSyncService.shared.configure(container: container)
        BackgroundRefresh.register()

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
            LockGate {
                RootView()
            }
            .task {
                    // First foreground of the session: pull anything that
                    // arrived while the app was closed.
                await MailSyncService.shared.syncIfDue()
            }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await MailSyncService.shared.syncIfDue() }
            case .background:
                BackgroundRefresh.schedule()
            default:
                break
            }
        }

        #if os(macOS)
        Settings {
            // SettingsView pushes to the review queue and export screens, so
            // the Settings scene needs its own stack — unlike on iOS it isn't
            // already inside RootView's.
            NavigationStack {
                SettingsView()
            }
            .modelContainer(container)
        }
        #endif
    }
}

// MARK: - Background refresh
//
// iOS only, and best-effort by design: the system decides when (and whether)
// to run it. Nothing is lost if it never fires — the alerts stay in Gmail and
// the next foreground sync picks them up.

enum BackgroundRefresh {

    static let taskIdentifier = "com.calebsung.PersonalOS.mailrefresh"

    static func register() {
        #if canImport(BackgroundTasks) && os(iOS)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            Task { @MainActor in
                let result = await MailSyncService.shared.syncNow()
                schedule()
                task.setTaskCompleted(success: result.errorMessage == nil)
            }
        }
        #endif
    }

    static func schedule() {
        #if canImport(BackgroundTasks) && os(iOS)
        guard MailSettings.autoSync, MailSettings.isConfigured else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
        #endif
    }
}
