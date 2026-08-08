import SwiftUI
import SwiftData

/// 대시보드 맨 위 "남은 돈" 카드. 기준점이 없으면 설정을 유도한다.
struct BalanceCard: View {
    @Environment(\.modelContext) private var context
    @Bindable var database: POSDatabase
    var onOpen: () -> Void = {}

    @State private var showingEditor = false
    @AppStorage(AmountPrivacy.key) private var hideAmounts = false

    private var snapshot: BalanceSnapshot? {
        BalanceService.snapshot(database: database, context: context)
    }

    var body: some View {
        Group {
            if let snapshot {
                filled(snapshot)
            } else {
                empty
            }
        }
        .glassCardStyle(interactive: true)
        .sheet(isPresented: $showingEditor) {
            BalanceEditorView(database: database)
        }
    }

    private func filled(_ snapshot: BalanceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            HStack {
                Text("남은 돈")
                    .font(Theme.caption().bold())
                    .foregroundStyle(.secondary)
                Spacer()
                // 남 앞에서 앱을 열 때를 위한 스위치. 설정의 "금액 가리기"와 같은 값.
                Button {
                    withAnimation(.snappy) { hideAmounts.toggle() }
                } label: {
                    Image(systemName: hideAmounts ? "eye.slash" : "eye")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            Text(AmountPrivacy.text(database.formattedAmount(snapshot.current), hidden: hideAmounts))
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(hideAmounts ? Color.secondary
                                 : (snapshot.current < 0 ? Theme.negativeRed : Color.primary))

            HStack(spacing: Theme.spacingM) {
                delta("나감", snapshot.spentSinceAnchor, Theme.expenseRed)
                delta("들어옴", snapshot.receivedSinceAnchor, Theme.incomeGreen)
            }

            Text(footnote(snapshot))
                .font(Theme.caption2())
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }

    private func delta(_ label: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(Theme.caption2())
                .foregroundStyle(.secondary)
            Text(AmountPrivacy.text(database.formattedAmount(value), hidden: hideAmounts))
                .font(Theme.caption().weight(.medium))
                .monospacedDigit()
        }
    }

    private func footnote(_ snapshot: BalanceSnapshot) -> String {
        let base = "\(snapshot.anchoredAt.formatted(date: .abbreviated, time: .omitted)) 기준 · 이후 \(snapshot.appliedCount)건 반영"
        return snapshot.isStale ? base + " · 한 번 맞춰볼 때가 됐어요" : base
    }

    private var empty: some View {
        Button {
            showingEditor = true
        } label: {
            HStack(spacing: Theme.spacingS) {
                Image(systemName: "banknote")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("남은 돈 보기")
                        .font(Theme.headline())
                    Text("지금 계좌 잔고를 한 번만 알려주면 이후 거래로 자동 계산해요")
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
