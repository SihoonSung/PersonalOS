import SwiftUI
import SwiftData

/// Edit a database's schema: rename, icon, and manage properties.
struct SchemaEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var database: POSDatabase
    @State private var editingProperty: POSProperty?

    var body: some View {
        NavigationStack {
            Form {
                Section("데이터베이스") {
                    TextField("이름", text: $database.name)
                    TextField("아이콘 (이모지)", text: $database.icon)
                }

                Section("속성") {
                    ForEach(database.orderedProperties, id: \.uuid) { property in
                        Button {
                            editingProperty = property
                        } label: {
                            HStack {
                                Image(systemName: property.type.systemImage)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)
                                Text(property.name)
                                Spacer()
                                Text(property.type.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onMove(perform: moveProperties)
                    .onDelete(perform: deleteProperties)

                    Button {
                        addProperty()
                    } label: {
                        Label("속성 추가", systemImage: "plus")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("속성 편집")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        try? context.save()
                        dismiss()
                    }
                }
            }
            .sheet(item: $editingProperty) { property in
                PropertyEditorView(property: property)
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        #endif
    }

    private func addProperty() {
        let nextIndex = (database.orderedProperties.map(\.sortIndex).max() ?? -1) + 1
        let property = POSProperty(name: "새 속성", type: .text, sortIndex: nextIndex)
        property.database = database
        context.insert(property)
        try? context.save()
        editingProperty = property
    }

    private func moveProperties(from source: IndexSet, to destination: Int) {
        var ordered = database.orderedProperties
        ordered.move(fromOffsets: source, toOffset: destination)
        for (i, property) in ordered.enumerated() {
            property.sortIndex = i
        }
        try? context.save()
    }

    private func deleteProperties(at offsets: IndexSet) {
        let ordered = database.orderedProperties
        for i in offsets {
            context.delete(ordered[i])
        }
        try? context.save()
    }
}

// MARK: - Single property editor

struct PropertyEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var property: POSProperty
    @State private var optionsText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("속성 이름", text: $property.name)
                    Picker("타입", selection: typeBinding) {
                        ForEach(PropertyType.allCases) { type in
                            Label(type.displayName, systemImage: type.systemImage).tag(type)
                        }
                    }
                }

                if property.type == .select {
                    Section("선택 옵션 (쉼표로 구분)") {
                        TextField("예: 식비, 교통, 쇼핑", text: $optionsText, axis: .vertical)
                            .onChange(of: optionsText) {
                                var config = property.config
                                config.selectOptions = optionsText
                                    .split(separator: ",")
                                    .map { $0.trimmingCharacters(in: .whitespaces) }
                                    .filter { !$0.isEmpty }
                                property.config = config
                            }
                    }
                }

                if property.type == .number {
                    Section("숫자 형식") {
                        Picker("형식", selection: numberFormatBinding) {
                            ForEach(NumberFormat.allCases) { format in
                                Text(format.displayName).tag(format)
                            }
                        }
                        if property.config.numberFormat == .currency {
                            TextField("통화 코드 (KRW, USD...)", text: currencyBinding)
                        }
                    }
                }

                if property.type == .date {
                    Section {
                        Toggle("시간 포함", isOn: includeTimeBinding)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("속성 설정")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        try? context.save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                optionsText = property.config.selectOptions.joined(separator: ", ")
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 360)
        #endif
    }

    private var typeBinding: Binding<PropertyType> {
        Binding(get: { property.type }, set: { property.type = $0 })
    }

    private var numberFormatBinding: Binding<NumberFormat> {
        Binding(
            get: { property.config.numberFormat },
            set: { var c = property.config; c.numberFormat = $0; property.config = c }
        )
    }

    private var currencyBinding: Binding<String> {
        Binding(
            get: { property.config.currencyCode },
            set: { var c = property.config; c.currencyCode = $0.uppercased(); property.config = c }
        )
    }

    private var includeTimeBinding: Binding<Bool> {
        Binding(
            get: { property.config.includeTime },
            set: { var c = property.config; c.includeTime = $0; property.config = c }
        )
    }
}
