import SwiftUI
import SwiftData

// MARK: - 검토 큐
//
// Imported transactions land here unreviewed. Fixing a category from this
// screen optionally teaches a rule, so the same merchant is filed correctly
// on its own next time.

struct ReviewQueueView: View {
    @Environment(\.modelContext) private var context
    @Bindable var database: POSDatabase

    @State private var teachingEntry: POSEntry?

    private var pending: [POSEntry] {
        guard let reviewed = database.reviewedProperty else { return [] }
        return (database.entries ?? [])
            .filter { $0.sourceKind == "email" && !$0.bool(for: reviewed) }
            .sorted { dateOf($0) > dateOf($1) }
    }

    private func dateOf(_ entry: POSEntry) -> Date {
        database.dateProperty.flatMap { entry.date(for: $0) } ?? entry.createdAt
    }

    var body: some View {
        Group {
            if pending.isEmpty {
                ContentUnavailableView(
                    "검토할 거래가 없어요",
                    systemImage: "checkmark.seal",
                    description: Text("메일에서 새 거래를 가져오면 여기에 쌓여요.")
                )
            } else {
                List {
                    Section {
                        ForEach(pending) { entry in
                            row(entry)
                        }
                    } footer: {
                        Text("카테고리를 고치면 같은 가게를 앞으로 자동으로 그 카테고리에 넣을지 물어봐요.")
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(DashboardBackground())
        .navigationTitle("검토 \(pending.count)건")
        .toolbar {
            if !pending.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("모두 확인") { confirmAll() }
                }
            }
        }
        .sheet(item: $teachingEntry) { entry in
            TeachRuleSheet(database: database, entry: entry)
        }
    }

    @ViewBuilder
    private func row(_ entry: POSEntry) -> some View {
        let amount = database.amountProperty.flatMap { entry.number(for: $0) } ?? 0
        let kind = entry.kind(in: database)
        let isIncome = EntryKind.sign(kind) > 0

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.title.isEmpty ? "(제목 없음)" : entry.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text((isIncome ? "+" : "") + database.formattedAmount(amount))
                    .monospacedDigit()
                    .foregroundStyle(isIncome ? Theme.incomeGreen : .primary)
            }

            HStack(spacing: 8) {
                Text(dateOf(entry).formatted(date: .abbreviated, time: .shortened))
                if let method = database.methodProperty.flatMap({ entry.text(for: $0) }) {
                    Text("·")
                    Text(method)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                kindMenu(entry, current: kind)
                if EntryKind.countsAsSpending(kind) {
                    categoryMenu(entry)
                }
                Spacer()
                Button {
                    confirm(entry)
                } label: {
                    Label("확인", systemImage: "checkmark")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.bold())
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button("삭제", role: .destructive) { delete(entry) }
        }
        .swipeActions(edge: .leading) {
            Button("확인") { confirm(entry) }.tint(.green)
        }
        .posRow()
    }

    /// 유형은 잔액 부호를 결정하니까 검토 화면에서 제일 먼저 손볼 수 있어야 한다.
    @ViewBuilder
    private func kindMenu(_ entry: POSEntry, current: String) -> some View {
        if let property = database.kindProperty {
            Menu {
                ForEach(EntryKind.all, id: \.self) { option in
                    Button {
                        entry.setText(option, for: property, context: context)
                        try? context.save()
                    } label: {
                        if option == current {
                            Label(option, systemImage: "checkmark")
                        } else {
                            Text(option)
                        }
                    }
                }
            } label: {
                Label(current, systemImage: EntryKind.sign(current) > 0 ? "arrow.down.left" : "arrow.up.right")
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func categoryMenu(_ entry: POSEntry) -> some View {
        if let property = database.categoryProperty {
            let current = entry.text(for: property) ?? "기타"
            Menu {
                ForEach(property.config.selectOptions, id: \.self) { option in
                    Button {
                        entry.setText(option, for: property, context: context)
                        try? context.save()
                        if option != current { teachingEntry = entry }
                    } label: {
                        if option == current {
                            Label(option, systemImage: "checkmark")
                        } else {
                            Text(option)
                        }
                    }
                }
            } label: {
                Label(current, systemImage: "tag")
                    .font(.caption)
            }
        }
    }

    private func confirm(_ entry: POSEntry) {
        guard let reviewed = database.reviewedProperty else { return }
        entry.setBool(true, for: reviewed, context: context)
        try? context.save()
        WidgetDataWriter.refresh(context: context)
        NotionSyncService.shared.scheduleAutoSync()
    }

    private func confirmAll() {
        guard let reviewed = database.reviewedProperty else { return }
        for entry in pending {
            entry.setBool(true, for: reviewed, context: context)
        }
        try? context.save()
        WidgetDataWriter.refresh(context: context)
        NotionSyncService.shared.scheduleAutoSync()
    }

    private func delete(_ entry: POSEntry) {
        NotionSyncService.shared.entryWillDelete(entry)
        context.delete(entry)
        try? context.save()
    }
}

// MARK: - "always file this merchant here"

private struct TeachRuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let database: POSDatabase
    let entry: POSEntry

    @State private var pattern = ""
    @State private var displayName = ""

    private var category: String {
        database.categoryProperty.flatMap { entry.text(for: $0) } ?? "기타"
    }

    private var rawSource: String {
        database.sourceProperty.flatMap { entry.text(for: $0) } ?? entry.title
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("가게 이름에 포함된 문구", text: $pattern)
                        .autocorrectionDisabled()
                    TextField("표시할 이름 (선택)", text: $displayName)
                        .autocorrectionDisabled()
                    LabeledContent("카테고리", value: category)
                } header: {
                    Text("규칙 저장")
                } footer: {
                    Text("원본: \(rawSource)\n앞으로 이 문구가 들어간 거래는 \(category)(으)로 자동 분류돼요.")
                }
            }
            .posForm()
            .navigationTitle("이 가게 기억하기")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("이번만") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("규칙 저장") {
                        CategoryRules.teach(
                            pattern: pattern,
                            category: category,
                            displayName: displayName.trimmingCharacters(in: .whitespaces),
                            context: context
                        )
                        dismiss()
                    }
                    .disabled(pattern.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                // Seed with the first couple of words of the raw merchant —
                // enough to match the chain, not so much that a store number
                // makes the rule useless.
                let words = rawSource
                    .components(separatedBy: " · ").first?
                    .split(separator: " ")
                    .prefix(2)
                    .joined(separator: " ") ?? ""
                pattern = words
                displayName = entry.title
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
    }
}
