import SwiftUI
import SwiftData

/// Natural-language quick add. Parsing always completes before saving
/// (no race between debounce and save — lesson from the previous app).
struct QuickAddBar: View {
    @Environment(\.modelContext) private var context
    let database: POSDatabase

    @State private var text = ""
    @State private var isSaving = false
    @ObservedObject private var ai = AIService.shared
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { submit() }
                .disabled(isSaving)
                .padding(.leading, 12)
                .padding(.vertical, 7)

            if isSaving {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 8)
            } else {
                Button {
                    submit()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.defaultAction)
                .disabled(text.isEmpty)
                .padding(.trailing, 3)
            }
        }
        .background(.quaternary.opacity(0.5), in: Capsule())
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var placeholder: String {
        switch database.templateKey {
        case TemplateKey.budget: return "예: 어제 스타벅스 5천원"
        case TemplateKey.todo: return "예: 내일 3시 회의 준비"
        default: return "자연어로 입력..."
        }
    }

    private func submit() {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, !isSaving else { return }
        isSaving = true

        Task {
            // Await full parse BEFORE saving — never save a half-parsed entry.
            let parsed = await ai.parse(input, database: database)
            save(parsed)
            text = ""
            isSaving = false
            focused = true
        }
    }

    @MainActor
    private func save(_ parsed: ParsedEntry) {
        let entry = POSEntry(title: parsed.title)
        entry.database = database
        context.insert(entry)

        for property in database.orderedProperties {
            if let t = parsed.texts[property.name] {
                entry.setText(t, for: property, context: context)
            }
            if let n = parsed.numbers[property.name] {
                entry.setNumber(n, for: property, context: context)
            }
            if let d = parsed.dates[property.name] {
                entry.setDate(d, for: property, context: context)
            }
            if let b = parsed.bools[property.name] {
                entry.setBool(b, for: property, context: context)
            }
        }
        try? context.save()
        NotionSyncService.shared.scheduleAutoSync()
    }
}
