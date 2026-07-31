import SwiftUI
import SwiftData

/// Navigation routes from the dashboard root.
enum Route: Hashable {
    case databases
    case database(POSDatabase)
    case settings
}

/// Root: 대시보드가 메인 화면. 좌상단 → 데이터베이스 목록, 우상단 → 설정.
struct RootView: View {
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            DashboardView(
                openDatabase: { path.append(.database($0)) },
                onOpenDatabases: { path.append(.databases) },
                onOpenSettings: { path.append(.settings) }
            )
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .databases:
                    DatabaseListView(openDatabase: { path.append(.database($0)) })
                case .database(let db):
                    DatabaseView(database: db)
                        .id(db.uuid)
                case .settings:
                    SettingsView()
                }
            }
        }
    }
}

/// 데이터베이스 목록 (구 사이드바) — 생성/삭제 지원.
struct DatabaseListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \POSDatabase.sortIndex) private var databases: [POSDatabase]
    var openDatabase: (POSDatabase) -> Void

    @State private var showingNewDatabase = false
    @State private var newDatabaseName = ""

    var body: some View {
        List {
            Section("데이터베이스") {
                ForEach(databases) { db in
                    Button {
                        openDatabase(db)
                    } label: {
                        HStack {
                            Label {
                                Text(db.name)
                                    .foregroundStyle(.primary)
                            } icon: {
                                Text(db.icon)
                            }
                            Spacer()
                            Text("\(db.entryCount)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .contextMenu {
                        Button("삭제", role: .destructive) { delete(db) }
                    }
                    .listRowBackground(Rectangle().fill(.ultraThinMaterial))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(DashboardBackground())
        .navigationTitle("데이터베이스")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewDatabase = true
                } label: {
                    Label("새 데이터베이스", systemImage: "plus")
                }
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

    private func createDatabase() {
        let name = newDatabaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let nextIndex = (databases.map(\.sortIndex).max() ?? -1) + 1
        let db = Templates.makeBlank(name: name, sortIndex: nextIndex)
        context.insert(db)
        try? context.save()
        newDatabaseName = ""
        openDatabase(db)
    }

    private func delete(_ db: POSDatabase) {
        context.delete(db)
        try? context.save()
    }
}
