import Foundation

// MARK: - 부하·회복 모델 v1
//
// 노션 Workout 페이지의 "⚙️ 부하·회복 모델 스펙 (v1)"을 그대로 옮긴 것.
// 밤 루틴이 하던 계산을 앱이 즉시 하므로 운동 중에도 "오늘 가슴 해도 되나"를
// 볼 수 있다.
//
// ── 스펙 해석 노트 ────────────────────────────────────────────────
// 원문은 1단계에서 "부위별 자극 점수"를 구하라 하고, 2단계에서 다시
// "보조 부위 = 주 부위의 50%"라고 해서 가중치가 두 번 나온다. 두 번 곱하면
// 5단계의 "보조는 세트×0.5로 가산"과 어긋나므로, **보조 0.5 가중을 부위별
// 점수 단계에서 한 번만** 적용한다. 그러면 1·2·5단계가 모두 일관된다.
// (이 해석이 앱의 기준이다 — 사용자가 앱을 데이터 주인으로 정했다.)

/// 엔진 입력 — SwiftData 에 의존하지 않는 순수 값. 그래서 파이썬 하네스로
/// 같은 케이스를 돌려 회귀 검증할 수 있다 (Tools/tests/muscle_load_check.py).
struct LoggedSet {
    let exerciseID: String
    let weight: Double
    let reps: Int
    let isWarmup: Bool

    init(exerciseID: String, weight: Double, reps: Int, isWarmup: Bool = false) {
        self.exerciseID = exerciseID
        self.weight = weight
        self.reps = reps
        self.isWarmup = isWarmup
    }
}

struct LoggedSession {
    let date: Date
    let sets: [LoggedSet]
    /// 세트 기록이 없을 때만 쓰는 부위 지정 (워치에서 온 유산소 등).
    let manualGroups: [MuscleGroup]

    init(date: Date, sets: [LoggedSet], manualGroups: [MuscleGroup] = []) {
        self.date = date
        self.sets = sets
        self.manualGroups = manualGroups
    }
}

enum SessionIntensity: String {
    case hard = "빡세게"
    case normal = "보통"
    case light = "가볍게"

    /// v1 §2 — 부여 피로도.
    var fatigue: Double {
        switch self {
        case .hard: return 100
        case .normal: return 70
        case .light: return 40
        }
    }
}

enum MuscleStatus: String {
    case fatigued = "피로"
    case recovering = "회복 중"
    case ready = "준비됨"

    var emoji: String {
        switch self {
        case .fatigued: return "🔴"
        case .recovering: return "🟡"
        case .ready: return "🟢"
        }
    }
}

struct MuscleState: Identifiable {
    let group: MuscleGroup
    /// 0~100.
    let fatigue: Double
    let status: MuscleStatus
    /// 피로도가 20 미만이 되는 시각 (이미 준비됐으면 nil).
    let recoveredAt: Date?
    /// 최근 7일 세트 수 (보조 부위는 0.5 가산).
    let weeklySets: Double

    var id: String { group.rawValue }

    /// v1 §5 — 부위당 주 10~20세트가 일반적 성장 구간.
    var volumeNote: String? {
        if weeklySets < 10 { return "부족" }
        if weeklySets > 20 { return "과다 주의" }
        return nil
    }
}

enum MuscleLoad {

    static let readyThreshold: Double = 20
    static let fatiguedThreshold: Double = 60
    /// 세트 기록이 없는 세션의 기본 자극 점수 (v1 §1).
    static let defaultScoreWithoutSets: Double = 6
    static let secondaryWeight: Double = 0.5

    // MARK: 1단계 — 강도계수와 부위별 자극 점수

    /// Epley 추정 1RM: 무게 × (1 + 횟수/30).
    static func estimatedOneRM(weight: Double, reps: Int) -> Double {
        guard weight > 0, reps > 0 else { return 0 }
        return weight * (1 + Double(reps) / 30)
    }

    /// v1 §1 — 최고세트무게 ÷ 1RM 기준으로 1.5 / 1.0 / 0.7.
    ///
    /// 실제 1RM이 없으면 그 세트에서 Epley로 추정하는데, 그러면 비율이
    /// 1/(1+reps/30)이 되어 **저반복일수록 강도계수가 높아진다** — 의도한 동작이다.
    static func intensityCoefficient(bestWeight: Double, reps: Int, knownOneRM: Double?) -> Double {
        let oneRM: Double
        if let knownOneRM, knownOneRM > 0 {
            oneRM = knownOneRM
        } else {
            oneRM = estimatedOneRM(weight: bestWeight, reps: reps)
        }
        guard oneRM > 0, bestWeight > 0 else { return 1.0 }
        let ratio = bestWeight / oneRM
        if ratio >= 0.85 { return 1.5 }
        if ratio >= 0.70 { return 1.0 }
        return 0.7
    }

    /// 세션 하나의 부위별 자극 점수.
    /// 주 부위는 그대로, 보조 부위는 0.5 가중으로 더한다.
    static func scores(for session: LoggedSession, oneRMs: [String: Double] = [:]) -> [MuscleGroup: Double] {
        let working = session.sets.filter { !$0.isWarmup }

        guard !working.isEmpty else {
            // 세트 기록 없음 → 지정 부위에 기본 점수.
            var result: [MuscleGroup: Double] = [:]
            for group in session.manualGroups {
                result[group, default: 0] += defaultScoreWithoutSets
            }
            return result
        }

        var result: [MuscleGroup: Double] = [:]
        let byExercise = Dictionary(grouping: working, by: \.exerciseID)

        for (exerciseID, rows) in byExercise {
            guard let exercise = ExerciseCatalog.find(exerciseID) else { continue }

            let coefficient: Double
            if exercise.usesLoad, let heaviest = rows.max(by: { $0.weight < $1.weight }), heaviest.weight > 0 {
                coefficient = intensityCoefficient(
                    bestWeight: heaviest.weight,
                    reps: heaviest.reps,
                    knownOneRM: oneRMs[exerciseID]
                )
            } else {
                // 맨몸·유산소는 무게로 강도를 잴 수 없다 → 보통 강도로 본다.
                coefficient = 1.0
            }

            let score = Double(rows.count) * coefficient
            for group in exercise.primary {
                result[group, default: 0] += score
            }
            for group in exercise.secondary {
                result[group, default: 0] += score * secondaryWeight
            }
        }
        return result
    }

    /// v1 §1 — 자극 점수 ≥ 9 빡세게 / 4~8 보통 / < 4 가볍게.
    static func intensity(for score: Double) -> SessionIntensity {
        if score >= 9 { return .hard }
        if score >= 4 { return .normal }
        return .light
    }

    // MARK: 3단계 — 감쇠

    /// 선형 감쇠: 부여 피로도 × max(0, 1 − 경과/T).
    static func decayed(fatigue: Double, hoursElapsed: Double, group: MuscleGroup) -> Double {
        let remaining = 1 - hoursElapsed / group.recoveryHours
        return fatigue * max(0, remaining)
    }

    // MARK: 종합

    /// 세션들을 받아 지금 시점의 부위별 상태를 계산한다.
    static func states(
        sessions: [LoggedSession],
        oneRMs: [String: Double] = [:],
        now: Date = .now
    ) -> [MuscleState] {
        var current: [MuscleGroup: Double] = [:]
        // 각 부위의 피로가 20 미만으로 떨어지는 가장 늦은 시각.
        var recoveryDeadline: [MuscleGroup: Date] = [:]
        var weekly: [MuscleGroup: Double] = [:]

        let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)

        for session in sessions {
            let hours = now.timeIntervalSince(session.date) / 3600
            guard hours >= 0 else { continue }

            let sessionScores = scores(for: session, oneRMs: oneRMs)

            for (group, score) in sessionScores {
                // 피로도 — 각 세션을 따로 감쇠시킨 뒤 합산 (v1 §3).
                let assigned = intensity(for: score).fatigue
                let remaining = decayed(fatigue: assigned, hoursElapsed: hours, group: group)
                if remaining > 0 {
                    current[group, default: 0] += remaining
                }

                // 회복 예상 시각 — 이 세션만 놓고 20 미만이 되는 때.
                if assigned > readyThreshold {
                    let hoursToReady = group.recoveryHours * (1 - readyThreshold / assigned)
                    let readyAt = session.date.addingTimeInterval(hoursToReady * 3600)
                    if readyAt > now {
                        recoveryDeadline[group] = max(recoveryDeadline[group] ?? readyAt, readyAt)
                    }
                }

                // 주간 세트 — 점수가 아니라 세트 수 기준 (v1 §5).
                if session.date >= weekAgo {
                    weekly[group, default: 0] += weeklySetCount(for: session, group: group)
                }
            }
        }

        return MuscleGroup.allCases.map { group in
            let fatigue = min(current[group] ?? 0, 100)
            let status: MuscleStatus
            if fatigue >= fatiguedThreshold { status = .fatigued }
            else if fatigue >= readyThreshold { status = .recovering }
            else { status = .ready }

            return MuscleState(
                group: group,
                fatigue: fatigue,
                status: status,
                recoveredAt: status == .ready ? nil : recoveryDeadline[group],
                weeklySets: weekly[group] ?? 0
            )
        }
    }

    /// v1 §5 — 주 부위는 세트 수 그대로, 보조 부위는 0.5.
    static func weeklySetCount(for session: LoggedSession, group: MuscleGroup) -> Double {
        let working = session.sets.filter { !$0.isWarmup }
        guard !working.isEmpty else {
            return session.manualGroups.contains(group) ? 1 : 0
        }
        var total: Double = 0
        for set in working {
            guard let exercise = ExerciseCatalog.find(set.exerciseID) else { continue }
            if exercise.primary.contains(group) { total += 1 }
            else if exercise.secondary.contains(group) { total += secondaryWeight }
        }
        return total
    }

    /// 오늘 해도 좋은 부위 — 준비됨인 것만, 주간 세트가 적은 순.
    static func suggestedGroups(from states: [MuscleState]) -> [MuscleGroup] {
        states
            .filter { $0.status == .ready }
            .sorted { $0.weeklySets < $1.weeklySets }
            .map(\.group)
    }
}
