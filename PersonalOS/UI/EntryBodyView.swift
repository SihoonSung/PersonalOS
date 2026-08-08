import SwiftUI
import SwiftData

/// 노션 페이지 본문 뷰어 + 덧붙이기.
///
/// 속성만 동기화하던 앱의 사각지대를 메운다 — 루틴이 매일 써 주는 글(영어
/// 미션, 투자 리포트, 종목 리서치)을 폰에서 읽고, 일기처럼 내가 쓸 자리에
/// 글을 덧붙일 수 있다.
///
/// 읽기 + 덧붙이기만 한다. 기존 블록은 고치지 않는다 (§NotionBlocks 참고).
struct EntryBodyView: View {
    let entry: POSEntry

    @State private var lines: [NotionBlockLine] = []
    @State private var isLoading = true
    @State private var errorText: String?

    @State private var draft = ""
    @State private var anchorID: String?
    @State private var isSending = false
    @FocusState private var composerFocused: Bool

    private var sections: [NotionBlockLine] {
        lines.filter(\.isSectionAnchor).filter { !$0.text.isEmpty }
    }

    private var anchorLabel: String {
        guard let anchorID, let match = sections.first(where: { $0.id == anchorID }) else {
            return "맨 끝에 추가"
        }
        return "\(match.text) 아래"
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("본문 불러오는 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText {
                ContentUnavailableView {
                    Label("본문을 불러오지 못했어요", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorText)
                } actions: {
                    Button("다시 시도") { Task { await load() } }
                }
            } else {
                content
            }
        }
        .navigationTitle(entry.title.isEmpty ? "본문" : entry.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom) { composer }
        .task { await load() }
    }

    // MARK: 본문

    private var content: some View {
        ScrollView {
            if lines.isEmpty {
                Text("본문이 비어 있어요. 아래에서 바로 쓸 수 있어요.")
                    .font(Theme.body())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.spacingM)
            } else {
                VStack(alignment: .leading, spacing: Theme.spacingS) {
                    ForEach(lines) { row(for: $0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.spacingM)
                .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func row(for line: NotionBlockLine) -> some View {
        switch line.kind {
        case .divider:
            Divider().padding(.vertical, 2)

        case .heading(let level):
            Text(line.text)
                .font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                .padding(.top, Theme.spacingS)

        case .bullet:
            bulletRow("•", line.text)

        case .numbered:
            bulletRow("—", line.text)

        case .todo(let checked):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(checked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                Text(line.text)
                    .font(Theme.body())
                    .strikethrough(checked)
                    .foregroundStyle(checked ? .secondary : .primary)
            }

        case .quote:
            HStack(alignment: .top, spacing: Theme.spacingS) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Theme.glassInk.opacity(0.25))
                    .frame(width: 3)
                Text(line.text)
                    .font(Theme.body())
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .code:
            Text(line.text)
                .font(.system(.caption, design: .monospaced))
                .padding(Theme.spacingS)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.glassTrack, in: RoundedRectangle(cornerRadius: Theme.radiusS))

        case .callout(let icon):
            HStack(alignment: .top, spacing: Theme.spacingS) {
                Text(icon)
                Text(line.text).font(Theme.body())
            }
            .padding(Theme.spacingS)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.glassTrack, in: RoundedRectangle(cornerRadius: Theme.radiusS))

        case .unsupported(let type):
            Text(line.text.isEmpty ? "[\(type)] 앱에서는 표시할 수 없어요" : line.text)
                .font(Theme.caption())
                .foregroundStyle(.tertiary)

        case .paragraph:
            if !line.text.isEmpty {
                Text(line.text)
                    .font(Theme.body())
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func bulletRow(_ marker: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker).foregroundStyle(.secondary)
            Text(text).font(Theme.body())
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: 작성

    private var composer: some View {
        VStack(spacing: Theme.spacingS) {
            if !sections.isEmpty {
                Menu {
                    Button("맨 끝에 추가") { anchorID = nil }
                    Divider()
                    ForEach(sections) { section in
                        Button(section.text) { anchorID = section.id }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "text.insert")
                        Text(anchorLabel).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .font(Theme.caption())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .bottom, spacing: Theme.spacingS) {
                TextField("여기에 써서 노션 본문에 추가", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($composerFocused)
                    .disabled(isSending)

                if isSending {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(Theme.spacingM)
        .background(.bar)
    }

    // MARK: 동작

    private func load() async {
        guard let pageID = entry.notionPageID else {
            errorText = "이 항목은 아직 노션에 올라가지 않았어요."
            isLoading = false
            return
        }
        isLoading = true
        errorText = nil
        do {
            let raw = try await NotionAPI.shared.blockChildren(of: pageID)
            lines = NotionBlocks.lines(from: raw)
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let pageID = entry.notionPageID, !isSending else { return }
        isSending = true
        defer { isSending = false }

        let children = NotionBlocks.paragraphs(from: text)
        guard !children.isEmpty else { return }
        do {
            try await NotionAPI.shared.appendBlocks(to: pageID, children: children, after: anchorID)
            draft = ""
            composerFocused = false
            await load()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
