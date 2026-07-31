import SwiftUI
import SwiftData

/// Root navigation: sidebar (databases) + detail (selected database).
/// NavigationSplitView collapses to a stack on iPhone automatically.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \POSDatabase.sortIndex) private var databases: [POSDatabase]

    @State private var selection: POSDatabase?
    @State private var showingNewDatabase = false
    @State private var newDatabaseName = ""

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let selection {
                DatabaseView(database: selection)
                    .id(selection.uuid)
            } else {
                ContentUnavailableView(
                    "데이터베이스를 선택하세요",
                    systemImage: "square.grid.2x2",
                    description: Text("왼쪽에서 선택하거나 새로 만들 수 있어요.")
                )
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
            Section("데이터베이스") {
                ForEach(databases) { db in
                    Label {
                        Text(db.name)
                    } icon: {
                        Text(db.icon)
                    }
                    .badge(db.entryCount)
                    .tag(db)
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
        selection = db
    }

    private func delete(_ db: POSDatabase) {
        if selection?.uuid == db.uuid { selection = nil }
        context.delete(db)
        try? context.save()
    }
}
