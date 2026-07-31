import SwiftUI
import SwiftData

// MARK: - Todo list (Reminders-style)
//
// Sections: 기한 지남 / 오늘 / 예정 / 기한 없음, with completed items tucked
// into a collapsible group at the bottom. Rows toggle with a circular
// checkmark like Reminders.

struct TodoView: View {
    @Environment(\.modelContext) private var context
    @Bindable var database: POSDatabase
    let searchText: String
    @Binding var editingEntry: POSEntry?

    @State private var showCompleted = false

    private var calendar: Calendar { .current }

    // MARK: Resolved rows

    private struct Item: Identifiable {
        let entry: POSEntry
        let done: Bool
        let due: Date?
        let priority: String?
        var id: UUID { entry.uuid }
    }

    private var allItems: [Item] {
        let doneProp = database.doneProperty
        let dateProp = database.dateProperty
        let priorityProp = database.priorityProperty
        var items = (database.entries ?? []).map { entry in
            Item(
                entry: entry,
                done: doneProp.map { entry.bool(for: $0) } ?? false,
                due: dateProp.flatMap { entry.date(for: $0) },
                priority: priorityProp.flatMap { entry.text(for: $0) }
            )
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            items = items.filter { $0.entry.title.lowercased().contains(query) }
        }
        return items
    }

    private var open: [Item] { allItems.filter { !$0.done } }

    private var overdue: [Item] {
        open.filter { item in
            guard let due = item.due else { return false }
            return due < calendar.startOfDay(for: .now)
        }
        .sorted { ($0.due ?? .distantPast) < ($1.due ?? .distantPast) }
    }

    private var today: [Item] {
        open.filter { $0.due.map { calendar.isDateInToday($0) } ?? false }
            .sorted { ($0.due ?? .now) < ($1.due ?? .now) }
    }

    private var upcoming: [Item] {
        open.filter { item in
            guard let due = item.due else { return false }
            return !calendar.isDateInToday(due) && due >= calendar.startOfDay(for: .now)
        }
        .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    private var someday: [Item] {
        open.filter { $0.due == nil }
            .sorted { $0.entry.createdAt > $1.entry.createdAt }
    }

    private var completed: [Item] {
        allItems.filter(\.done)
            .sorted { $0.entry.updatedAt > $1.entry.updatedAt }
    }

    // MARK: Body

    var body: some View {
        if !searchText.isEmpty && allItems.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            list
        }
    }

    private var list: some View {
        List {
            if !overdue.isEmpty {
                Section {
                    ForEach(overdue) { row($0) }
                } header: {
                    Label("기한 지남", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
            }
            if !today.isEmpty {
                Section("오늘") {
                    ForEach(today) { row($0) }
                }
            }
            if !upcoming.isEmpty {
                Section("예정") {
                    ForEach(upcoming) { row($0) }
                }
            }
            if !someday.isEmpty {
                Section("기한 없음") {
                    ForEach(someday) { row($0) }
                }
            }
            if !completed.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showCompleted) {
                        ForEach(completed) { row($0) }
                    } label: {
                        Text("완료됨")
                            .foregroundStyle(.secondary)
                            .badge(completed.count)
                    }
                }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #else
        .listStyle(.insetGrouped)
        #endif
    }

    // MARK: Row

    private func row(_ item: Item) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                toggle(item)
            } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.done ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if let mark = priorityMark(item.priority) {
                        Text(mark)
                            .foregroundStyle(.orange)
                            .fontWeight(.semibold)
                    }
                    Text(item.entry.title.isEmpty ? "(제목 없음)" : item.entry.title)
                        .strikethrough(item.done)
                        .foregroundStyle(item.done ? .secondary : .primary)
                        .lineLimit(2)
                }
                if let due = item.due {
                    Text(dueText(due))
                        .font(.caption)
                        .foregroundStyle(isOverdue(due) && !item.done ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { editingEntry = item.entry }
        .swipeActions(edge: .trailing) {
            Button("삭제", role: .destructive) { delete(item.entry) }
        }
        .contextMenu {
            Button("편집") { editingEntry = item.entry }
            Button("삭제", role: .destructive) { delete(item.entry) }
        }
    }

    private func priorityMark(_ priority: String?) -> String? {
        switch priority {
        case "높음": return "!!!"
        case "보통": return nil
        case "낮음": return nil
        default: return nil
        }
    }

    private func isOverdue(_ due: Date) -> Bool {
        due < calendar.startOfDay(for: .now)
    }

    private func dueText(_ due: Date) -> String {
        let includeTime = database.dateProperty?.config.includeTime ?? false
        let timePart = includeTime ? " " + due.formatted(date: .omitted, time: .shortened) : ""
        if calendar.isDateInToday(due) { return "오늘" + timePart }
        if calendar.isDateInTomorrow(due) { return "내일" + timePart }
        if calendar.isDateInYesterday(due) { return "어제" + timePart }
        return due.formatted(.dateTime.month().day().weekday(.abbreviated)) + timePart
    }

    // MARK: Actions

    private func toggle(_ item: Item) {
        guard let doneProp = database.doneProperty else { return }
        withAnimation(.snappy) {
            item.entry.setBool(!item.done, for: doneProp, context: context)
            try? context.save()
        }
        NotionSyncService.shared.scheduleAutoSync()
    }

    private func delete(_ entry: POSEntry) {
        NotionSyncService.shared.entryWillDelete(entry)
        context.delete(entry)
        try? context.save()
    }
}
