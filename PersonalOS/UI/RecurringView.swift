import SwiftUI
import SwiftData

// MARK: - 고정지출
//
// 등록하는 화면이 아니라 **읽는** 화면이다. 목록은 전부 거래 기록에서
// 추론한 것이고, 사용자가 손댈 게 없다.

struct RecurringView: View {
    @Environment(\.modelContext) private var context
    @Bindable var database: POSDatabase

    private var charges: [RecurringCharge] {
        RecurringDetector.detect(in: database)
    }

    var body: some View {
        let all = charges
        let active = all.filter { !$0.looksDormant() }
        let dormant = all.filter { $0.looksDormant() }

        Group {
            if all.isEmpty {
                ContentUnavailableView(
                    "아직 정기 결제를 못 찾았어요",
                    systemImage: "arrow.trianglehead.2.clockwise",
                    description: Text("같은 곳에서 일정한 간격으로 3번 이상 결제되면 여기에 잡혀요. 메일을 더 가져오면 빨리 잡힙니다.")
                )
            } else {
                List {
                    Section {
                        summary(active)
                    }
                    .posRow()

                    if !active.isEmpty {
                        Section("다음 결제") {
                            ForEach(active) { charge in
                                row(charge)
                            }
                        }
                        .posRow()
                    }

                    if !dormant.isEmpty {
                        Section {
                            ForEach(dormant) { charge in
                                row(charge, dormant: true)
                            }
                        } header: {
                            Text("멈춘 것 같아요")
                        } footer: {
                            Text("주기가 두 번 넘게 지나도록 결제가 없었어요. 해지했다면 그대로 두면 됩니다.")
                        }
                        .posRow()
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(DashboardBackground())
        .navigationTitle("고정지출")
    }

    private func summary(_ active: [RecurringCharge]) -> some View {
        let monthly = RecurringDetector.monthlyEquivalent(active)
        let remaining = RecurringDetector.remainingThisMonth(active)
        let balance = BalanceService.snapshot(database: database, context: context)

        return VStack(alignment: .leading, spacing: 10) {
            Text("한 달 고정지출")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(database.formattedAmount(monthly))
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            HStack(spacing: 0) {
                stat("건수", "\(active.count)개")
                stat("이번 달 남음", database.formattedAmount(remaining))
                if let balance {
                    stat("쓸 수 있는 돈", database.formattedAmount(balance.current - remaining))
                }
            }

            if let balance, balance.current - remaining < 0 {
                Label("고정지출을 빼면 잔액이 모자라요", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ charge: RecurringCharge, dormant: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(charge.displayName)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(charge.cadenceLabel)
                    Text("·")
                    Text(charge.category)
                    if !dormant {
                        Text("·")
                        Text(dueLabel(charge.nextDueDate))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if charge.priceChanged {
                    Text("금액 변동: 평소 \(database.formattedAmount(charge.typicalAmount)) → 최근 \(database.formattedAmount(charge.lastAmount))")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Text(database.formattedAmount(charge.typicalAmount))
                .font(.body.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(dormant ? .secondary : .primary)
        }
        .padding(.vertical, 2)
    }

    private func dueLabel(_ date: Date) -> String {
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: date)
        ).day ?? 0
        switch days {
        case ..<0: return "지남"
        case 0: return "오늘"
        case 1: return "내일"
        case 2...13: return "\(days)일 뒤"
        default: return date.formatted(.dateTime.month().day())
        }
    }
}

// MARK: - 대시보드 카드

struct FixedCostCard: View {
    @Environment(\.modelContext) private var context
    @Bindable var database: POSDatabase
    var onOpen: () -> Void = {}

    var body: some View {
        let active = RecurringDetector.detect(in: database).filter { !$0.looksDormant() }
        let monthly = RecurringDetector.monthlyEquivalent(active)

        Group {
            if active.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: Theme.spacingXS) {
                    HStack {
                        Text("고정지출")
                            .font(Theme.caption().bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(database.formattedAmount(monthly))
                        .font(Theme.title())
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("월 \(active.count)건")
                        .font(Theme.caption2())
                        .foregroundStyle(.secondary)

                    if let next = active.first {
                        Text("다음 · \(next.displayName) \(database.formattedAmount(next.typicalAmount))")
                            .font(Theme.caption2())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCardStyle(interactive: true)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)
            }
        }
    }
}
