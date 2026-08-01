import SwiftUI
import SwiftData

/// Dynamic form for one entry, driven by the database schema.
struct EntryDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var entry: POSEntry
    let database: POSDatabase

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("제목", text: $entry.title)
                        .font(.headline)
                }
                Section {
                    ForEach(database.orderedProperties, id: \.uuid) { property in
                        PropertyFieldView(entry: entry, property: property)
                    }
                }
                Section {
                    LabeledContent("생성", value: entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("수정", value: entry.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
                Section {
                    Button("항목 삭제", role: .destructive) {
                        NotionSyncService.shared.entryWillDelete(entry)
                        context.delete(entry)
                        try? context.save()
                        dismiss()
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(entry.title.isEmpty ? "새 항목" : entry.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        entry.touch()
                        try? context.save()
                        NotionSyncService.shared.scheduleAutoSync()
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }
}

// MARK: - One field, typed by the property

struct PropertyFieldView: View {
    @Environment(\.modelContext) private var context
    let entry: POSEntry
    let property: POSProperty

    var body: some View {
        switch property.type {
        case .text:
            TextField(property.name, text: textBinding, axis: .vertical)

        case .url:
            TextField(property.name, text: textBinding)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif

        case .number:
            HStack {
                Text(property.name)
                Spacer()
                TextField("0", text: numberBinding)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .frame(maxWidth: 160)
                if property.config.numberFormat == .currency {
                    Text(property.config.currencyCode)
                        .foregroundStyle(.secondary)
                }
            }

        case .checkbox:
            Toggle(property.name, isOn: boolBinding)

        case .date:
            VStack(alignment: .leading, spacing: 6) {
                if entry.date(for: property) != nil {
                    DatePicker(
                        property.name,
                        selection: dateBinding,
                        displayedComponents: property.config.includeTime ? [.date, .hourAndMinute] : [.date]
                    )
                    Button("날짜 지우기") {
                        entry.setDate(nil, for: property, context: context)
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                } else {
                    HStack {
                        Text(property.name)
                        Spacer()
                        Button("날짜 추가") {
                            entry.setDate(.now, for: property, context: context)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

        case .multiSelect:
            let selected = entry.textList(for: property)
            DisclosureGroup {
                ForEach(property.config.selectOptions, id: \.self) { option in
                    Button {
                        var list = entry.textList(for: property)
                        if let i = list.firstIndex(of: option) {
                            list.remove(at: i)
                        } else {
                            list.append(option)
                        }
                        entry.setTextList(list, for: property, context: context)
                    } label: {
                        HStack {
                            Text(option)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selected.contains(option) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } label: {
                HStack {
                    Text(property.name)
                    Spacer()
                    Text(selected.isEmpty ? "없음" : selected.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

        case .select:
            Picker(property.name, selection: selectBinding) {
                Text("없음").tag("")
                ForEach(property.config.selectOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
        }
    }

    // MARK: Bindings

    private var textBinding: Binding<String> {
        Binding(
            get: { entry.text(for: property) ?? "" },
            set: { entry.setText($0, for: property, context: context) }
        )
    }

    private var numberBinding: Binding<String> {
        Binding(
            get: {
                guard let n = entry.number(for: property) else { return "" }
                return n.truncatingRemainder(dividingBy: 1) == 0
                    ? String(Int(n))
                    : String(n)
            },
            set: { raw in
                entry.setNumber(Self.sanitizedDouble(raw), for: property, context: context)
            }
        )
    }

    private var boolBinding: Binding<Bool> {
        Binding(
            get: { entry.bool(for: property) },
            set: { entry.setBool($0, for: property, context: context) }
        )
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { entry.date(for: property) ?? .now },
            set: { entry.setDate($0, for: property, context: context) }
        )
    }

    private var selectBinding: Binding<String> {
        Binding(
            get: { entry.text(for: property) ?? "" },
            set: { entry.setText($0.isEmpty ? nil : $0, for: property, context: context) }
        )
    }

    /// Tolerant numeric parsing: keeps digits, one decimal point, leading minus.
    static func sanitizedDouble(_ raw: String) -> Double? {
        var result = ""
        var seenDot = false
        for (i, ch) in raw.enumerated() {
            if ch.isNumber {
                result.append(ch)
            } else if ch == "." && !seenDot {
                seenDot = true
                result.append(ch)
            } else if ch == "-" && i == 0 {
                result.append(ch)
            }
        }
        return Double(result)
    }
}
