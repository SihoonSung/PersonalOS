import SwiftUI
import SwiftData

// MARK: - 잔액 기준점
//
// 은행 잔고를 읽어올 수 없으니 사용자가 "지금 통장에 이만큼 있다"를 한 번
// 적어주면, 그 뒤 거래를 가감해 현재 잔액을 만든다. 숫자가 어긋나면 새로
// 적어서 다시 맞추면 된다.

struct BalanceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let database: POSDatabase

    @State private var input = ""
    @State private var anchors: [POSBalanceAnchor] = []

    private var parsedAmount: Double? {
        let cleaned = input
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    private var preview: BalanceSnapshot? {
        guard let amount = parsedAmount else { return nil }
        return BalanceService.snapshot(database: database, anchorAmount: amount, anchoredAt: .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("예: 1250.40", text: $input)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                    }
                } header: {
                    Text("지금 계좌 잔고")
                } footer: {
                    Text("Chase 앱이나 웹에서 보이는 현재 잔고를 그대로 적어 주세요. 지금 이 순간을 기준으로 잡고, 이후 들어오는 거래를 더하고 빼서 잔액을 보여줍니다.")
                }

                if let preview, preview.appliedCount > 0 {
                    Section("저장하면") {
                        LabeledContent("반영될 이후 거래", value: "\(preview.appliedCount)건")
                            .foregroundStyle(.secondary)
                        Text("기준 시각 이후에 기록된 거래가 \(preview.appliedCount)건 있어요. 이 거래들이 이미 잔고에 반영된 상태라면 그대로 두면 되고, 아직 안 빠진 상태라면 잔액이 이중으로 계산될 수 있어요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !anchors.isEmpty {
                    Section("기록") {
                        ForEach(anchors) { anchor in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(database.formattedAmount(anchor.amount))
                                        .monospacedDigit()
                                    Text(anchor.recordedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if anchor.uuid == anchors.first?.uuid {
                                    Text("현재 기준")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("삭제", role: .destructive) {
                                    BalanceService.delete(anchor, context: context)
                                    reload()
                                }
                            }
                        }
                    }
                }
            }
            .posForm()
            .navigationTitle("잔액 기준점")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        if let amount = parsedAmount {
                            BalanceService.setAnchor(amount: amount, context: context)
                        }
                        dismiss()
                    }
                    .disabled(parsedAmount == nil)
                }
            }
            .onAppear(perform: reload)
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        #endif
    }

    private func reload() {
        anchors = BalanceService.allAnchors(context: context)
    }
}
