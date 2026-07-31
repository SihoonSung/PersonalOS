import SwiftUI
import SwiftData

/// Sidebar selection: 홈 대시보드 or a user database.
enum SidebarSelection: Hashable {
    case home
    case database(POSDatabase)
}

/// Root navigation: sidebar (홈 + databases) + detail.
/// NavigationSplitView collapses to a stack on iPhone automatically.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \POSDatabase.sortIndex) private var databases: [POSDatabase]

    @State private var selection: SidebarSelection? = .home
    @State private var showingNewDatabase = false
    @State private var newDatabaseName = ""

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            switch selection {
            case .database(let db):
                DatabaseView(database: db)
                    .id(db.uuid)
            default:
                DashboardView(openDatabase: { selection = .database($0) })
            }
        }
        .alert("새 데이터베이스", isPresented: $showingNewDatabase) {
            TextField("이름", text: $newDatabaseName)
            Button("만들기") { createDatabase() }
            Button("취소", role: .cancel) { newDatabaseName = "" }
        } message: {
            Text("빈 데이터베이스를 만들고 속성은 나중에 추가할 수 있어요.")
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Label(L.tabHome, systemImage: "house")
                .tag(SidebarSelection.home)

            Section("데이터베이스") {
                ForEach(databases) { db in
                    Label {
                        Text(db.name)
                    } icon: {
                        Text(db.icon)
                    }
                    .badge(db.entryCount)
                    .tag(SidebarSelection.database(db))
                    .contextMenu {
                        Button("삭제", role: .destructive) { delete(db) }
                    }
                }
            }
        }
        .navigationTitle("PersonalOS")
        .toolbar {
            ToolbarItem {
                Button {
                    showingNewDatabase = true
                } label: {
                    Label("새 데이터베이스", systemImage: "plus")
                }
            }
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("설정", systemImage: "gearshape")
                }
            }
            #endif
        }
    }

    private func createDatabase() {
        let name = newDatabaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let nextIndex = (databases.map(\.sortIndex).max() ?? -1) + 1
        let db = Templates.makeBlank(name: name, sortIndex: nextIndex)
        context.insert(db)
        try? context.save()
        newDatabaseName = ""
        selection = .database(db)
    }

    private func delete(_ db: POSDatabase) {
        if case .database(let selected) = selection, selected.uuid == db.uuid {
            selection = .home
        }
        context.delete(db)
        try? context.save()
    }
}
