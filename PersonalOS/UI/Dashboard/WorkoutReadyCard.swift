import SwiftUI
import SwiftData

/// 대시보드 운동 카드 — "오늘 뭐 해도 되지?"에 한눈에 답한다.
struct WorkoutReadyCard: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \POSWorkoutSession.startedAt, order: .reverse) private var sessions: [POSWorkoutSession]
    var onOpen: () -> Void = {}

    private var calendar: Calendar { .current }

    var body: some View {
        let states = MuscleLoad.states(
            sessions: WorkoutStore.loggedSessions(sessions),
            oneRMs: WorkoutStore.oneRMs(context: context)
        )
        let ready = MuscleLoad.suggestedGroups(from: states).prefix(3)
        let fatigued = states.filter { $0.status == .fatigued }
        let thisWeek = sessions.filter { calendar.isDate($0.startedAt, equalTo: .now, toGranularity: .weekOfYear) }.count

        VStack(alignment: .leading, spacing: Theme.spacingS) {
            HStack {
                Text("운동")
                    .font(Theme.caption().bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("이번 주 \(thisWeek)회")
                    .font(Theme.caption())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(Theme.caption())
                    .foregroundStyle(.secondary)
            }

            if sessions.isEmpty {
                Text("첫 운동을 기록해보세요")
                    .font(Theme.body())
                    .foregroundStyle(.secondary)
            } else {
                Text(ready.isEmpty ? "전 부위 회복 중" : ready.map(\.rawValue).joined(separator: " · "))
                    .font(.title3.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(ready.isEmpty ? "오늘은 쉬어도 좋아요" : "오늘 하기 좋은 부위")
                    .font(Theme.caption2())
                    .foregroundStyle(.secondary)

                if !fatigued.isEmpty {
                    HStack(spacing: Theme.spacingXS) {
                        ForEach(fatigued.prefix(4)) { state in
                            Text("🔴 \(state.group.rawValue)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.glassTrack, in: Capsule())
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle()
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}
