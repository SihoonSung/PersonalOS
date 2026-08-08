import Foundation
import SwiftData

// MARK: - 운동 기록 모델
//
// 가계부·할 일과 달리 운동은 범용 DB 엔진(POSDatabase/POSEntry) 위에 얹지
// 않는다. 세트는 "행 하나에 값 여러 개"가 아니라 **한 종목 아래 여러 행**이라
// 속성 테이블로 표현하면 조회가 지저분해진다. 전용 모델을 쓰고, 노션에는
// 세션 요약을 한 줄로 밀어 넣는다.
//
// CloudKit 규칙 유지: 저장 속성은 기본값 또는 옵셔널, @Attribute(.unique) 금지,
// 관계는 옵셔널 + inverse 는 "다" 쪽에 선언.

@Model
final class POSWorkoutSession {
    var uuid: UUID = UUID()
    var startedAt: Date = Date.now
    var endedAt: Date?
    var note: String = ""

    /// 애플 헬스에서 읽어온 세션이면 그쪽 UUID — 재수입 중복을 막는 키.
    var healthKitUUID: String?
    /// 앱에서 기록해 헬스에 써 넣은 세션인지.
    var pushedToHealthKit: Bool = false

    /// 세트가 없는 세션(워치 유산소 등)의 부위. 쉼표 구분 원문.
    var manualGroupsRaw: String = ""
    /// 유산소 지속 시간(분) — 세트가 없을 때 부하 추정에 쓴다.
    var durationMinutes: Double = 0

    /// 노션 운동 기록 DB에 만들어진 항목 (있으면 갱신, 없으면 생성).
    var notionEntryUUID: UUID?

    @Relationship(deleteRule: .cascade, inverse: \POSWorkoutSet.session)
    var sets: [POSWorkoutSet]? = []

    init(startedAt: Date = .now) {
        self.uuid = UUID()
        self.startedAt = startedAt
    }

    var orderedSets: [POSWorkoutSet] {
        (sets ?? []).sorted { $0.order < $1.order }
    }

    var manualGroups: [MuscleGroup] {
        get {
            manualGroupsRaw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .compactMap { MuscleGroup(rawValue: $0) }
        }
        set { manualGroupsRaw = newValue.map(\.rawValue).joined(separator: ", ") }
    }

    /// 세트에서 실제로 자극한 부위 (주 + 보조), 없으면 수동 지정 부위.
    var involvedGroups: [MuscleGroup] {
        var found: Set<MuscleGroup> = []
        for set in sets ?? [] {
            guard let exercise = ExerciseCatalog.find(set.exerciseID) else { continue }
            found.formUnion(exercise.primary)
            found.formUnion(exercise.secondary)
        }
        if found.isEmpty { return manualGroups }
        return MuscleGroup.allCases.filter { found.contains($0) }
    }

    /// "벤치프레스 135x5x5, 스쿼트 185x8x3" — 노션 메모 형식과 같다.
    var setSummary: String {
        let grouped = Dictionary(grouping: orderedSets, by: \.exerciseID)
        return grouped.keys.sorted().compactMap { id -> String? in
            guard let rows = grouped[id], let exercise = ExerciseCatalog.find(id) else { return nil }
            guard let heaviest = rows.max(by: { $0.weight < $1.weight }) else { return nil }
            if exercise.usesLoad {
                let weight = heaviest.weight.formatted(.number.precision(.fractionLength(0...1)))
                return "\(exercise.name) \(weight)x\(heaviest.reps)x\(rows.count)"
            }
            return "\(exercise.name) \(heaviest.reps)회x\(rows.count)"
        }.joined(separator: ", ")
    }

    var totalSets: Int { (sets ?? []).count }

    /// 총 볼륨 (무게 × 횟수 합) — 무게 있는 종목만.
    var totalVolume: Double {
        (sets ?? []).reduce(0) { $0 + $1.weight * Double($1.reps) }
    }
}

@Model
final class POSWorkoutSet {
    var uuid: UUID = UUID()
    var exerciseID: String = ""
    /// lb 기준. 맨몸/유산소는 0.
    var weight: Double = 0
    var reps: Int = 0
    var order: Int = 0
    /// 워밍업 세트는 부하 계산에서 뺀다.
    var isWarmup: Bool = false

    var session: POSWorkoutSession?

    init(exerciseID: String, weight: Double = 0, reps: Int = 0, order: Int = 0, isWarmup: Bool = false) {
        self.uuid = UUID()
        self.exerciseID = exerciseID
        self.weight = weight
        self.reps = reps
        self.order = order
        self.isWarmup = isWarmup
    }

    var exercise: Exercise? { ExerciseCatalog.find(exerciseID) }
}

/// 사용자가 직접 넣은 1RM. 없으면 Epley 추정으로 대체한다 (부하 모델 v1 §1).
@Model
final class POSOneRepMax {
    var uuid: UUID = UUID()
    var exerciseID: String = ""
    var weight: Double = 0
    var recordedAt: Date = Date.now

    init(exerciseID: String, weight: Double, recordedAt: Date = .now) {
        self.uuid = UUID()
        self.exerciseID = exerciseID
        self.weight = weight
        self.recordedAt = recordedAt
    }
}
