import SwiftUI
import SwiftData

/// One database: entries list (iPhone) / table (Mac) + quick add + schema editing.
struct DatabaseView: View {
    @Environment(\.modelContext) private var context
    @Bindable var database: POSDatabase

    @State private var searchText = ""
    @State private var editingEntry: POSEntry?
    @State private var showingSchemaEditor = false
    @State private var sortDescending = true
    #if os(macOS)
    @State private var tableSelection = Set<PersistentIdentifier>()
    #endif

    private var filteredEntries: [POSEntry] {
        var list = database.entries ?? []
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter { entry in
                if entry.title.lowercased().contains(q) { return true }
                return (entry.values ?? []).contains {
                    $0.textValue?.lowercased().contains(q) == true
                }
            }
        }
        list.sort {
            sortDescending ? $0.createdAt > $1.createdAt : $0.createdAt < $1.createdAt
        }
        return list
    }

    var body: some View {
        content
        .background(DashboardBackground())
        .safeAreaInset(edge: .bottom) {
            QuickAddBar(database: database, style: .glass)
                .padding(.horizontal, Theme.spacingM)
                .padding(.bottom, Theme.spacingS)
        }
        .navigationTitle(database.name)
        .searchable(text: $searchText, prompt: "검색")
        .toolbar {
            ToolbarItemGroup {
                if database.notionSyncEnabled {
                    Button {
                        Task { await NotionSyncService.shared.syncNow(database) }
                    } label: {
                        Label("Notion 동기화", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                #if canImport(PhotosUI) && os(iOS)
                if database.templateKey == TemplateKey.budget {
                    CapturePickerButton(database: database)
                }
                #endif
                if database.templateKey == TemplateKey.budget && MailSettings.isConfigured {
                    Button {
                        Task { await MailSyncService.shared.syncNow() }
                    } label: {
                        Label("메일 가져오기", systemImage: "envelope.arrow.triangle.branch")
                    }
                    .disabled(MailSyncService.shared.isSyncing)
                }
                if !isTemplateView {
                    Menu {
                        Picker("정렬", selection: $sortDescending) {
                            Text("최신순").tag(true)
                            Text("오래된순").tag(false)
                        }
                    } label: {
                        Label("정렬", systemImage: "arrow.up.arrow.down")
                    }
                }
                Button {
                    showingSchemaEditor = true
                } label: {
                    Label("속성 편집", systemImage: "slider.horizontal.3")
                }
                Button {
                    addEntry()
                } label: {
                    Label("새 항목", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editingEntry) { entry in
            EntryDetailView(entry: entry, database: database)
        }
        .sheet(isPresented: $showingSchemaEditor) {
            SchemaEditorView(database: database)
        }
    }

    // MARK: - Platform content

    @ViewBuilder
    private var content: some View {
        if (database.entries ?? []).isEmpty {
            ContentUnavailableView(
                "아직 항목이 없어요",
                systemImage: "tray",
                description: Text("아래 입력창에 자연어로 입력하거나 + 버튼을 누르세요.")
            )
            .frame(maxHeight: .infinity)
        } else {
            switch database.templateKey {
            case TemplateKey.budget:
                BudgetView(database: database, searchText: searchText, editingEntry: $editingEntry)
            case TemplateKey.sermon:
                SermonListView(database: database, searchText: searchText, editingEntry: $editingEntry)
            case TemplateKey.todo:
                TodoView(database: database, searchText: searchText, editingEntry: $editingEntry)
            default:
                if filteredEntries.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxHeight: .infinity)
                } else {
                    #if os(macOS)
                    entryTable
                    #else
                    entryList
                    #endif
                }
            }
        }
    }

    private var isTemplateView: Bool {
        database.templateKey == TemplateKey.budget || database.templateKey == TemplateKey.todo
    }

    private var entryList: some View {
        List {
            ForEach(filteredEntries) { entry in
                EntryRowView(entry: entry, database: database)
                    .contentShape(Rectangle())
                    .onTapGesture { editingEntry = entry }
                    .posRow()
            }
            .onDelete { offsets in
                let items = filteredEntries
                for i in offsets { delete(items[i]) }
            }
        }
        .posList()
    }

    #if os(macOS)
    private var entryTable: some View {
        Table(filteredEntries, selection: $tableSelection) {
            TableColumn("제목") { entry in
                Text(entry.title.isEmpty ? "(제목 없음)" : entry.title)
                    .fontWeight(.medium)
            }
            TableColumnForEach(database.orderedProperties, id: \.uuid) { property in
                TableColumn(property.name) { entry in
                    Text(entry.displayString(for: property))
                        .foregroundStyle(property.type == .date ? .secondary : .primary)
                }
            }
        }
        .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
            Button("편집") {
                if let id = ids.first,
                   let entry = filteredEntries.first(where: { $0.persistentModelID == id }) {
                    editingEntry = entry
                }
            }
            Button("삭제", role: .destructive) {
                for id in ids {
                    if let entry = filteredEntries.first(where: { $0.persistentModelID == id }) {
                        delete(entry)
                    }
                }
            }
        } primaryAction: { ids in
            if let id = ids.first,
               let entry = filteredEntries.first(where: { $0.persistentModelID == id }) {
                editingEntry = entry
            }
        }
    }
    #endif

    // MARK: - Actions

    private func addEntry() {
        let entry = POSEntry()
        entry.database = database
        context.insert(entry)
        try? context.save()
        editingEntry = entry
    }

    private func delete(_ entry: POSEntry) {
        NotionSyncService.shared.entryWillDelete(entry)
        context.delete(entry)
        try? context.save()
    }
}

// MARK: - iPhone row

struct EntryRowView: View {
    let entry: POSEntry
    let database: POSDatabase

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.title.isEmpty ? "(제목 없음)" : entry.title)
                .fontWeight(.medium)
                .lineLimit(1)
            let values = database.orderedProperties
                .map { entry.displayString(for: $0) }
                .filter { !$0.isEmpty }
                .prefix(4)
            if !values.isEmpty {
                Text(values.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
