import SwiftUI
import SwiftData
#if canImport(PhotosUI)
import PhotosUI
#endif

// MARK: - 스크린샷으로 읽은 거래 확인하고 저장
//
// 조용히 저장하지 않는 게 핵심이다. OCR은 메일 파싱과 달리 틀릴 수 있고,
// 무엇보다 "이 돈을 왜 보냈는지"는 화면에 안 적혀 있어서 사람이 써야 한다.
// 그래서 읽은 값은 **초안**으로만 채우고 저장은 사람이 누른다.

struct CaptureReviewSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let database: POSDatabase
    let scan: ReceiptScan
    var imageData: Data?

    @State private var amount: Double?
    @State private var title = ""
    @State private var kind = EntryKind.expense
    @State private var category = "기타"
    @State private var date = Date.now
    @State private var memo = ""
    @State private var loaded = false

    private var categories: [String] {
        database.categoryProperty?.config.selectOptions ?? Templates.budgetCategories
    }

    /// 같은 날 · 같은 금액 · 비슷한 제목이 이미 있으면 알려준다.
    /// 스크린샷을 두 번 공유하거나, 메일 수집과 겹치는 걸 잡기 위한 것.
    private var duplicate: POSEntry? {
        guard let amount, let amountProperty = database.amountProperty else { return nil }
        let calendar = Calendar.current
        return (database.entries ?? []).first { entry in
            guard let other = entry.number(for: amountProperty),
                  abs(other - amount) < 0.005,
                  calendar.isDate(entry.effectiveDate(in: database), inSameDayAs: date)
            else { return false }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let imageData {
                    Section {
                        CaptureThumbnail(data: imageData)
                            .frame(maxWidth: .infinity)
                    }
                }

                Section {
                    HStack {
                        Text("금액")
                        Spacer()
                        Text(database.amountProperty?.config.currencyCode ?? "USD")
                            .font(Theme.caption())
                            .foregroundStyle(.secondary)
                        PosNumberField(placeholder: "0.00", value: amount) { amount = $0 }
                            .frame(maxWidth: 120)
                    }

                    TextField("받는 사람 / 가맹점", text: $title)

                    Picker("유형", selection: $kind) {
                        ForEach(EntryKind.all, id: \.self) { Text($0).tag($0) }
                    }

                    Picker("카테고리", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }

                    DatePicker("날짜", selection: $date)
                } header: {
                    Text(scan.source.isEmpty ? "읽은 내용" : "\(scan.source)에서 읽은 내용")
                } footer: {
                    if scan.amount == nil {
                        Text("금액을 못 읽었어요. 직접 적어주세요.")
                    }
                }

                Section {
                    // 자동 포커스는 일부러 안 준다 — 키보드가 바로 올라오면
                    // 위쪽의 금액·상대를 확인하기 전에 화면을 가린다.
                    TextField("예: 룸메 8월 전기세 정산", text: $memo, axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text("왜 보냈는지")
                } footer: {
                    Text("화면에 안 적혀 있는 유일한 정보예요. 나중에 이 줄만 보고도 알아볼 수 있게 적어두면 좋아요.")
                }

                if let duplicate {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("같은 날 같은 금액이 이미 있어요")
                                Text(duplicate.title.isEmpty ? "(제목 없음)" : duplicate.title)
                                    .font(Theme.caption())
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                if !scan.lines.isEmpty {
                    Section {
                        DisclosureGroup("화면에서 읽은 글자 \(scan.lines.count)줄") {
                            ForEach(Array(scan.lines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .posForm()
            .navigationTitle("스크린샷에서 기록")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .disabled(amount == nil)
                }
            }
            .onAppear(perform: prefill)
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }

    // MARK: 초안 채우기

    private func prefill() {
        guard !loaded else { return }
        loaded = true

        amount = scan.amount.map { abs($0) }
        date = scan.date ?? .now
        memo = scan.memo ?? ""

        let raw = scan.counterparty ?? ""
        title = raw.isEmpty
            ? scan.source
            : CategoryRules.displayName(for: raw, fallback: raw, context: context)

        // 같은 상대의 지난 기록이 있으면 그때 고른 유형·카테고리를 따라간다.
        // 한 번 고쳐두면 다음부터 안 고쳐도 되게 만드는 부분.
        if let previous = lastEntry(matching: raw.isEmpty ? title : raw) {
            kind = previous.kind(in: database)
            if let property = database.categoryProperty,
               let value = previous.text(for: property) {
                category = value
            }
        } else {
            kind = scan.suggestedKind
            category = EntryKind.countsAsSpending(scan.suggestedKind)
                ? CategoryRules.category(for: raw, context: context)
                : "금융"
        }

        if !categories.contains(category) { category = categories.first ?? "기타" }
    }

    private func lastEntry(matching name: String) -> POSEntry? {
        let needle = name.trimmingCharacters(in: .whitespaces).uppercased()
        guard needle.count >= 2 else { return nil }
        return (database.entries ?? [])
            .filter { $0.title.uppercased().contains(needle) || needle.contains($0.title.uppercased()) }
            .filter { !$0.title.isEmpty }
            .max { $0.createdAt < $1.createdAt }
    }

    // MARK: 저장

    private func save() {
        guard let amount else { return }

        let entry = POSEntry(title: title.isEmpty ? "이체" : title)
        context.insert(entry)
        entry.database = database
        entry.sourceKind = "capture"

        if let property = database.amountProperty {
            entry.setNumber(abs(amount), for: property, context: context)
        }
        if let property = database.dateProperty {
            entry.setDate(date, for: property, context: context)
        }
        if let property = database.kindProperty {
            entry.setText(kind, for: property, context: context)
        }
        if let property = database.categoryProperty {
            entry.setText(category, for: property, context: context)
        }
        if let property = database.memoProperty, !memo.isEmpty {
            entry.setText(memo, for: property, context: context)
        }
        if let property = database.methodProperty, !scan.source.isEmpty {
            entry.setText(scan.source, for: property, context: context)
        }
        // 사람이 확인하고 누른 것이므로 검토 대기에 넣지 않는다.
        if let property = database.reviewedProperty {
            entry.setBool(true, for: property, context: context)
        }

        // 다음에 같은 상대를 읽으면 카테고리를 자동으로 맞춘다.
        if let raw = scan.counterparty, !raw.isEmpty {
            CategoryRules.teach(
                pattern: raw,
                category: category,
                displayName: title == raw ? "" : title,
                context: context
            )
        }

        try? context.save()
        WidgetDataWriter.refresh(context: context)
        NotionSyncService.shared.scheduleAutoSync()
        dismiss()
    }
}

// MARK: - 스크린샷 미리보기

struct CaptureThumbnail: View {
    let data: Data

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                placeholder
            }
            #elseif canImport(AppKit)
            if let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                placeholder
            }
            #else
            placeholder
            #endif
        }
        .frame(maxHeight: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .font(.largeTitle)
            .foregroundStyle(.tertiary)
    }
}

// MARK: - 사진 보관함에서 고르기
//
// 단축어를 아직 안 만들었거나, 지난 스크린샷을 뒤늦게 넣을 때 쓰는 길.
// 공유 시트 경로와 같은 파서·같은 확인 시트를 쓴다.

#if canImport(PhotosUI)
struct CapturePickerButton: View {
    let database: POSDatabase

    @State private var selection: PhotosPickerItem?
    @State private var pending: (scan: ReceiptScan, data: Data)?
    @State private var errorMessage: String?
    @State private var isReading = false

    var body: some View {
        PhotosPicker(selection: $selection, matching: .screenshots) {
            Label("스크린샷에서 기록", systemImage: "text.viewfinder")
        }
        .disabled(isReading)
        .onChange(of: selection) { _, item in
            guard let item else { return }
            isReading = true
            Task {
                defer { isReading = false; selection = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        errorMessage = ReceiptOCR.Failure.unreadableImage.localizedDescription
                        return
                    }
                    pending = (try ReceiptOCR.scan(from: data), data)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .sheet(isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            if let pending {
                CaptureReviewSheet(database: database, scan: pending.scan, imageData: pending.data)
            }
        }
        .alert("읽지 못했어요", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("확인", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
}
#endif
