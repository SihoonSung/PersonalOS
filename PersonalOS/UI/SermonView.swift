import SwiftUI
import SwiftData

// MARK: - 말씀 기록
//
// 주일마다 한 편. 예배 중에 빠르게 적는 게 전부라, 범용 항목 폼 대신
// 전용 화면을 둔다 — 노트 칸이 크고, 본문은 아무 형식으로 쳐도 정규화되고,
// 적용점은 바로 할 일로 보낼 수 있다.

struct SermonListView: View {
    @Environment(\.modelContext) private var context
    @Bindable var database: POSDatabase
    let searchText: String
    @Binding var editingEntry: POSEntry?

    @State private var editing: POSEntry?

    private var calendar: Calendar { .current }

    private struct Item: Identifiable {
        let entry: POSEntry
        let date: Date
        let passage: String
        let preacher: String
        var id: UUID { entry.uuid }
    }

    private var items: [Item] {
        let dateProp = database.dateProperty
        let passageProp = database.orderedProperties.first { $0.name == "본문" }
        let preacherProp = database.orderedProperties.first { $0.name == "설교자" }

        var list = (database.entries ?? []).map { entry in
            Item(
                entry: entry,
                date: dateProp.flatMap { entry.date(for: $0) } ?? entry.createdAt,
                passage: passageProp.flatMap { entry.text(for: $0) } ?? "",
                preacher: preacherProp.flatMap { entry.text(for: $0) } ?? ""
            )
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter {
                $0.entry.title.lowercased().contains(q)
                    || $0.passage.lowercased().contains(q)
                    || $0.preacher.lowercased().contains(q)
            }
        }
        return list.sorted { $0.date > $1.date }
    }

    /// 가장 가까운 지난 주일 (오늘이 주일이면 오늘).
    private var lastSunday: Date {
        let today = calendar.startOfDay(for: .now)
        let weekday = calendar.component(.weekday, from: today)   // 1 = 일요일
        return calendar.date(byAdding: .day, value: -(weekday - 1), to: today) ?? today
    }

    private var hasThisSunday: Bool {
        items.contains { calendar.isDate($0.date, inSameDayAs: lastSunday) }
    }

    var body: some View {
        List {
            if !hasThisSunday && searchText.isEmpty {
                Section {
                    Button {
                        editing = createSermon(on: lastSunday)
                    } label: {
                        PosRow(
                            calendar.isDateInToday(lastSunday) ? "오늘 설교 기록하기" : "지난 주일 설교 기록하기",
                            systemImage: "square.and.pencil",
                            subtitle: lastSunday.formatted(.dateTime.month().day().weekday(.wide)),
                            showsChevron: true
                        ) { EmptyView() }
                    }
                    .buttonStyle(.plain)
                }
                .posRow()
            }

            if items.isEmpty {
                Section {
                    Text(searchText.isEmpty ? "아직 기록이 없어요." : "검색 결과가 없어요.")
                        .foregroundStyle(.secondary)
                }
                .posRow()
            }

            ForEach(groupedByMonth(), id: \.key) { group in
                Section(group.key) {
                    ForEach(group.items) { item in
                        Button { editing = item.entry } label: { row(item) }
                            .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        let list = group.items
                        for index in offsets { delete(list[index].entry) }
                    }
                }
                .posRow()
            }
        }
        .posList()
        .sheet(item: $editing) { entry in
            SermonEditorView(database: database, entry: entry)
        }
    }

    private func groupedByMonth() -> [(key: String, items: [Item])] {
        Dictionary(grouping: items) { $0.date.formatted(.dateTime.year().month(.wide)) }
            .map { (key: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { ($0.items.first?.date ?? .distantPast) > ($1.items.first?.date ?? .distantPast) }
    }

    private func row(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.entry.title.isEmpty ? "(제목 없음)" : item.entry.title)
                    .font(Theme.body().bold())
                    .lineLimit(1)
                Spacer()
                Text(item.date.formatted(.dateTime.month().day()))
                    .font(Theme.caption2())
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            HStack(spacing: 6) {
                if !item.passage.isEmpty {
                    Text(item.passage)
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)
                }
                if !item.preacher.isEmpty {
                    Text("·").foregroundStyle(.tertiary)
                    Text(item.preacher)
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private func createSermon(on date: Date) -> POSEntry {
        let entry = POSEntry()
        entry.database = database
        context.insert(entry)
        if let dateProp = database.dateProperty {
            entry.setDate(date, for: dateProp, context: context)
        }
        try? context.save()
        return entry
    }

    private func delete(_ entry: POSEntry) {
        NotionSyncService.shared.entryWillDelete(entry)
        context.delete(entry)
        try? context.save()
    }
}

// MARK: - 기록/편집

struct SermonEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let database: POSDatabase
    @Bindable var entry: POSEntry

    @State private var showingBookPicker = false
    @State private var sentToTodo = false

    private func property(_ name: String) -> POSProperty? {
        database.orderedProperties.first { $0.name == name }
    }

    private func text(_ name: String) -> String {
        property(name).flatMap { entry.text(for: $0) } ?? ""
    }

    private func binding(_ name: String) -> Binding<String> {
        Binding(
            get: { text(name) },
            set: { value in
                guard let prop = property(name) else { return }
                entry.setText(value, for: prop, context: context)
            }
        )
    }

    private var parsedPassage: BibleReference? {
        BibleCanon.parse(text("본문"))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacingL) {
                    GlassSection("설교") {
                        TextField("제목", text: $entry.title, axis: .vertical)
                            .font(Theme.headline())
                            .lineLimit(1...2)
                            .onChange(of: entry.title) { entry.touch() }

                        PosDivider()

                        if let dateProp = database.dateProperty {
                            DatePicker(
                                "날짜",
                                selection: Binding(
                                    get: { entry.date(for: dateProp) ?? .now },
                                    set: { entry.setDate($0, for: dateProp, context: context) }
                                ),
                                displayedComponents: [.date]
                            )
                            .font(Theme.body())
                            PosDivider()
                        }

                        HStack {
                            Text("설교자")
                                .font(Theme.body())
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .leading)
                            TextField("이름", text: binding("설교자"))
                                .textFieldStyle(.plain)
                        }
                    }

                    GlassSection("본문", footnote: passageFootnote) {
                        HStack(spacing: Theme.spacingS) {
                            TextField("예: 요 3:16 또는 요한복음 3장 16절", text: binding("본문"))
                                .textFieldStyle(.plain)
                            Button {
                                showingBookPicker = true
                            } label: {
                                Image(systemName: "book")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    GlassSection("노트") {
                        TextField("들으면서 적기", text: binding("노트"), axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(6...30)
                            .font(Theme.body())
                    }

                    GlassSection("은혜 구절") {
                        TextField("마음에 남은 구절", text: binding("은혜 구절"), axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(1...6)
                    }

                    GlassSection("적용", footnote: "이번 주에 실제로 할 한 가지를 적어 두면 할 일로 보낼 수 있어요.") {
                        TextField("이번 주에 할 한 가지", text: binding("적용"), axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(1...5)

                        if !text("적용").isEmpty {
                            PosDivider()
                            Button {
                                sendApplicationToTodo()
                            } label: {
                                PosRow(sentToTodo ? "할 일에 추가됨" : "할 일로 보내기",
                                       systemImage: sentToTodo ? "checkmark.circle.fill" : "arrow.turn.up.right") {
                                    EmptyView()
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(sentToTodo)
                            .foregroundStyle(sentToTodo ? Color.secondary : Color.primary)
                        }
                    }

                    if entry.notionPageID != nil {
                        NavigationLink {
                            EntryBodyView(entry: entry)
                        } label: {
                            GlassSection {
                                PosRow("노션 본문", systemImage: "doc.text", showsChevron: true) { EmptyView() }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: Theme.spacingXL)
                }
                .padding(Theme.spacingM)
            }
            .posScreen()
            .navigationTitle("말씀 기록")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { save() }.bold()
                }
            }
            .sheet(isPresented: $showingBookPicker) {
                BibleBookPickerView { book in
                    binding("본문").wrappedValue = "\(book.name) "
                }
            }
        }
    }

    private var passageFootnote: String? {
        guard !text("본문").isEmpty else { return nil }
        if let parsed = parsedPassage {
            return "\(parsed.book.testamentName) · \(parsed.display) 로 저장돼요"
        }
        return "책 이름을 알아보지 못했어요. 적은 그대로 저장됩니다."
    }

    private func save() {
        // 본문은 저장 시점에 한 형식으로 맞춘다 — 나중에 정렬·검색이 되게.
        if let prop = property("본문") {
            let normalized = BibleCanon.normalize(text("본문"))
            if !normalized.isEmpty { entry.setText(normalized, for: prop, context: context) }
        }
        if entry.title.isEmpty, let parsed = parsedPassage {
            entry.title = parsed.display
        }
        entry.touch()
        try? context.save()
        NotionSyncService.shared.scheduleAutoSync()
        dismiss()
    }

    /// 적용점을 할 일 데이터베이스에 항목으로 만든다.
    private func sendApplicationToTodo() {
        let all = (try? context.fetch(FetchDescriptor<POSDatabase>())) ?? []
        guard let todo = all.first(where: { $0.templateKey == TemplateKey.todo }) else { return }

        let task = POSEntry(title: text("적용"))
        task.database = todo
        context.insert(task)
        if let due = todo.dateProperty {
            // 다음 주일 전까지 — 한 주의 적용이니까.
            let next = Calendar.current.date(byAdding: .day, value: 6, to: .now) ?? .now
            task.setDate(next, for: due, context: context)
        }
        if let memo = todo.orderedProperties.first(where: { $0.name == "메모" }) {
            let source = entry.title.isEmpty ? text("본문") : entry.title
            task.setText("말씀 적용 · \(source)", for: memo, context: context)
        }
        try? context.save()
        NotionSyncService.shared.scheduleAutoSync()
        withAnimation { sentToTodo = true }
    }
}

// MARK: - 성경 책 고르기

struct BibleBookPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (BibleBook) -> Void

    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach([true, false], id: \.self) { isOld in
                    let books = BibleCanon.search(query).filter { $0.isOldTestament == isOld }
                    if !books.isEmpty {
                        Section(isOld ? "구약" : "신약") {
                            ForEach(books) { book in
                                Button {
                                    onPick(book)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(book.name)
                                        Spacer()
                                        Text(book.abbreviation)
                                            .font(Theme.caption())
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .posRow()
                    }
                }
            }
            .posList()
            .searchable(text: $query, prompt: "책 이름")
            .navigationTitle("성경")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
        }
    }
}
