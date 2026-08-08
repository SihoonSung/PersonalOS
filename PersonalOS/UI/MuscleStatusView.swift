import SwiftUI
import SwiftData

/// 부위별 피로도 · 회복 예상 · 주간 볼륨.
/// 노션 "🫀 근육 상태" DB가 밤마다 하던 걸 앱이 즉시 계산해 보여준다.
struct MuscleStatusView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \POSWorkoutSession.startedAt, order: .reverse) private var sessions: [POSWorkoutSession]

    private var states: [MuscleState] {
        // @Query 결과가 바뀔 때마다 다시 계산된다 (세션 수가 적어 비용 무시 가능).
        MuscleLoad.states(
            sessions: WorkoutStore.loggedSessions(sessions),
            oneRMs: WorkoutStore.oneRMs(context: context)
        )
    }

    var body: some View {
        let states = states
        let ready = MuscleLoad.suggestedGroups(from: states)

        List {
            if !ready.isEmpty {
                Section {
                    Text(ready.prefix(3).map(\.rawValue).joined(separator: " · "))
                        .font(Theme.body().bold())
                    Text("회복됐고 이번 주 볼륨이 적은 순이에요.")
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)
                } header: {
                    Text("오늘 하기 좋은 부위")
                }
                .posRow()
            }

            Section {
                ForEach(states) { state in
                    row(state)
                }
            } header: {
                Text("부위별 상태")
            } footer: {
                Text("피로도 60↑ 🔴 · 20~59 🟡 · 20↓ 🟢. 회복 시간은 가슴·등·하체 72시간, 어깨·팔·코어 48시간, 심폐 24시간 기준이에요.")
            }
            .posRow()
        }
        .posList()
        .navigationTitle("근육 상태")
    }

    private func row(_ state: MuscleState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Theme.spacingS) {
                Text(state.status.emoji)
                Text(state.group.rawValue)
                    .font(Theme.body().bold())
                Spacer()
                Text(state.status.rawValue)
                    .font(Theme.caption())
                    .foregroundStyle(.secondary)
                Text("\(Int(state.fatigue.rounded()))")
                    .font(Theme.caption().bold())
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            ZStack(alignment: .leading) {
                Capsule().fill(Theme.glassTrack)
                GeometryReader { geo in
                    Capsule()
                        .fill(color(for: state.status))
                        .frame(width: geo.size.width * min(state.fatigue / 100, 1))
                }
            }
            .frame(height: 5)

            HStack(spacing: Theme.spacingS) {
                Text("주간 \(state.weeklySets.formatted(.number.precision(.fractionLength(0...1))))세트")
                    .font(Theme.caption2())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if let note = state.volumeNote {
                    Text(note)
                        .font(Theme.caption2().bold())
                        .foregroundStyle(note == "부족" ? .orange : .red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background((note == "부족" ? Color.orange : Color.red).opacity(0.12), in: Capsule())
                }

                Spacer()

                if let recoveredAt = state.recoveredAt {
                    Text("\(recoveredAt.formatted(.relative(presentation: .named))) 회복")
                        .font(Theme.caption2())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func color(for status: MuscleStatus) -> Color {
        switch status {
        case .fatigued: return .red.opacity(0.75)
        case .recovering: return .orange.opacity(0.75)
        case .ready: return Theme.glassInk.opacity(0.4)
        }
    }
}
