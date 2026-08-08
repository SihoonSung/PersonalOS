import Foundation

// MARK: - 부위
//
// 노션 "🏋️ 운동 기록"의 부위 multi_select 와 값이 정확히 같아야 동기화된다.
// 회복 시간도 여기 묶어 둔다 (부하·회복 모델 v1 §3).

enum MuscleGroup: String, CaseIterable, Identifiable, Codable {
    case chest = "가슴"
    case back = "등"
    case shoulder = "어깨"
    case legs = "하체"
    case arms = "팔"
    case core = "코어"
    case cardio = "심폐"

    var id: String { rawValue }

    /// 피로가 0까지 선형으로 빠지는 데 걸리는 시간.
    var recoveryHours: Double {
        switch self {
        case .chest, .back, .legs: return 72
        case .shoulder, .arms, .core: return 48
        case .cardio: return 24
        }
    }

    var symbol: String {
        switch self {
        case .chest: return "figure.strengthtraining.traditional"
        case .back: return "figure.rower"
        case .shoulder: return "figure.arms.open"
        case .legs: return "figure.squat"
        case .arms: return "dumbbell"
        case .core: return "figure.core.training"
        case .cardio: return "heart.fill"
        }
    }
}

enum Equipment: String, CaseIterable, Identifiable, Codable {
    case barbell = "바벨"
    case dumbbell = "덤벨"
    case machine = "머신"
    case cable = "케이블"
    case bodyweight = "맨몸"
    case kettlebell = "케틀벨"
    case cardio = "유산소"

    var id: String { rawValue }
}

// MARK: - 종목

struct Exercise: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let equipment: Equipment
    let primary: [MuscleGroup]
    let secondary: [MuscleGroup]
    /// 무게를 기록하는 종목인지. 맨몸·유산소는 false → 강도계수 계산에서 빠진다.
    let usesLoad: Bool

    var isCardio: Bool { primary.contains(.cardio) }

    var muscleSummary: String {
        (primary + secondary).map(\.rawValue).joined(separator: " · ")
    }
}

enum ExerciseCatalog {

    /// 검색·정렬은 이 배열 하나로 끝난다 (개인용 규모라 인덱스 불필요).
    static let all: [Exercise] = [
        // ── 가슴
        ex("bench-press", "벤치프레스", .barbell, [.chest], [.arms, .shoulder]),
        ex("incline-bench-press", "인클라인 벤치프레스", .barbell, [.chest], [.shoulder, .arms]),
        ex("decline-bench-press", "디클라인 벤치프레스", .barbell, [.chest], [.arms]),
        ex("db-bench-press", "덤벨 벤치프레스", .dumbbell, [.chest], [.arms, .shoulder]),
        ex("db-incline-press", "인클라인 덤벨프레스", .dumbbell, [.chest], [.shoulder, .arms]),
        ex("db-fly", "덤벨 플라이", .dumbbell, [.chest], []),
        ex("cable-fly", "케이블 플라이", .cable, [.chest], []),
        ex("pec-deck", "펙덱 플라이", .machine, [.chest], []),
        ex("chest-press-machine", "체스트 프레스 머신", .machine, [.chest], [.arms]),
        ex("push-up", "푸시업", .bodyweight, [.chest], [.arms, .core], usesLoad: false),
        ex("dip-chest", "딥스 (가슴)", .bodyweight, [.chest], [.arms], usesLoad: false),

        // ── 등
        ex("deadlift", "데드리프트", .barbell, [.back], [.legs, .core]),
        ex("barbell-row", "바벨로우", .barbell, [.back], [.arms]),
        ex("pendlay-row", "펜들레이 로우", .barbell, [.back], [.arms]),
        ex("t-bar-row", "티바로우", .barbell, [.back], [.arms]),
        ex("db-row", "덤벨로우", .dumbbell, [.back], [.arms]),
        ex("seated-cable-row", "시티드 케이블로우", .cable, [.back], [.arms]),
        ex("lat-pulldown", "랫풀다운", .cable, [.back], [.arms]),
        ex("straight-arm-pulldown", "스트레이트암 풀다운", .cable, [.back], []),
        ex("pull-up", "풀업", .bodyweight, [.back], [.arms], usesLoad: false),
        ex("chin-up", "친업", .bodyweight, [.back], [.arms], usesLoad: false),
        ex("machine-row", "머신 로우", .machine, [.back], [.arms]),
        ex("rack-pull", "랙풀", .barbell, [.back], [.legs]),
        ex("hyperextension", "백 익스텐션", .bodyweight, [.back], [.core], usesLoad: false),
        ex("shrug", "슈러그", .dumbbell, [.back], [.shoulder]),

        // ── 어깨
        ex("overhead-press", "오버헤드 프레스", .barbell, [.shoulder], [.arms, .core]),
        ex("db-shoulder-press", "덤벨 숄더프레스", .dumbbell, [.shoulder], [.arms]),
        ex("arnold-press", "아놀드 프레스", .dumbbell, [.shoulder], [.arms]),
        ex("lateral-raise", "사이드 레터럴 레이즈", .dumbbell, [.shoulder], []),
        ex("front-raise", "프론트 레이즈", .dumbbell, [.shoulder], []),
        ex("rear-delt-fly", "리어 델트 플라이", .dumbbell, [.shoulder], [.back]),
        ex("face-pull", "페이스풀", .cable, [.shoulder], [.back]),
        ex("upright-row", "업라이트 로우", .barbell, [.shoulder], [.arms]),
        ex("shoulder-press-machine", "숄더프레스 머신", .machine, [.shoulder], [.arms]),
        ex("cable-lateral-raise", "케이블 레터럴 레이즈", .cable, [.shoulder], []),

        // ── 하체
        ex("back-squat", "백스쿼트", .barbell, [.legs], [.core, .back]),
        ex("front-squat", "프론트스쿼트", .barbell, [.legs], [.core]),
        ex("goblet-squat", "고블릿 스쿼트", .dumbbell, [.legs], [.core]),
        ex("hack-squat", "핵스쿼트", .machine, [.legs], []),
        ex("leg-press", "레그프레스", .machine, [.legs], []),
        ex("romanian-deadlift", "루마니안 데드리프트", .barbell, [.legs], [.back]),
        ex("stiff-leg-deadlift", "스티프레그 데드리프트", .barbell, [.legs], [.back]),
        ex("lunge", "런지", .dumbbell, [.legs], [.core]),
        ex("bulgarian-split-squat", "불가리안 스플릿 스쿼트", .dumbbell, [.legs], [.core]),
        ex("step-up", "스텝업", .dumbbell, [.legs], [.core]),
        ex("leg-extension", "레그 익스텐션", .machine, [.legs], []),
        ex("leg-curl", "레그컬", .machine, [.legs], []),
        ex("hip-thrust", "힙 쓰러스트", .barbell, [.legs], [.core]),
        ex("glute-bridge", "글루트 브릿지", .bodyweight, [.legs], [.core], usesLoad: false),
        ex("calf-raise", "카프레이즈", .machine, [.legs], []),
        ex("hip-abduction", "힙 어브덕션", .machine, [.legs], []),
        ex("walking-lunge", "워킹 런지", .bodyweight, [.legs], [.core], usesLoad: false),

        // ── 팔
        ex("barbell-curl", "바벨 컬", .barbell, [.arms], []),
        ex("db-curl", "덤벨 컬", .dumbbell, [.arms], []),
        ex("hammer-curl", "해머 컬", .dumbbell, [.arms], []),
        ex("preacher-curl", "프리처 컬", .machine, [.arms], []),
        ex("incline-db-curl", "인클라인 덤벨 컬", .dumbbell, [.arms], []),
        ex("cable-curl", "케이블 컬", .cable, [.arms], []),
        ex("concentration-curl", "컨센트레이션 컬", .dumbbell, [.arms], []),
        ex("triceps-pushdown", "트라이셉스 푸시다운", .cable, [.arms], []),
        ex("rope-pushdown", "로프 푸시다운", .cable, [.arms], []),
        ex("overhead-triceps-ext", "오버헤드 트라이셉스 익스텐션", .dumbbell, [.arms], []),
        ex("skull-crusher", "스컬 크러셔", .barbell, [.arms], []),
        ex("close-grip-bench", "클로즈그립 벤치프레스", .barbell, [.arms], [.chest]),
        ex("dip-triceps", "딥스 (삼두)", .bodyweight, [.arms], [.chest], usesLoad: false),
        ex("kickback", "킥백", .dumbbell, [.arms], []),
        ex("wrist-curl", "리스트 컬", .dumbbell, [.arms], []),

        // ── 코어
        ex("plank", "플랭크", .bodyweight, [.core], [], usesLoad: false),
        ex("side-plank", "사이드 플랭크", .bodyweight, [.core], [], usesLoad: false),
        ex("crunch", "크런치", .bodyweight, [.core], [], usesLoad: false),
        ex("hanging-leg-raise", "행잉 레그레이즈", .bodyweight, [.core], [], usesLoad: false),
        ex("cable-crunch", "케이블 크런치", .cable, [.core], []),
        ex("russian-twist", "러시안 트위스트", .bodyweight, [.core], [], usesLoad: false),
        ex("ab-rollout", "앱 롤아웃", .bodyweight, [.core], [.back], usesLoad: false),
        ex("mountain-climber", "마운틴 클라이머", .bodyweight, [.core], [.cardio], usesLoad: false),
        ex("dead-bug", "데드버그", .bodyweight, [.core], [], usesLoad: false),
        ex("farmer-carry", "파머스 워크", .dumbbell, [.core], [.back]),
        ex("kb-swing", "케틀벨 스윙", .kettlebell, [.core], [.legs, .back]),

        // ── 심폐
        ex("running", "러닝", .cardio, [.cardio], [.legs], usesLoad: false),
        ex("treadmill", "트레드밀", .cardio, [.cardio], [.legs], usesLoad: false),
        ex("cycling", "사이클", .cardio, [.cardio], [.legs], usesLoad: false),
        ex("rowing-machine", "로잉 머신", .cardio, [.cardio], [.back, .legs], usesLoad: false),
        ex("stair-climber", "스텝밀", .cardio, [.cardio], [.legs], usesLoad: false),
        ex("elliptical", "일립티컬", .cardio, [.cardio], [.legs], usesLoad: false),
        ex("jump-rope", "줄넘기", .cardio, [.cardio], [.legs], usesLoad: false),
        ex("burpee", "버피", .bodyweight, [.cardio], [.legs, .chest], usesLoad: false),
        ex("hiit", "HIIT 서킷", .cardio, [.cardio], [.legs, .core], usesLoad: false),
        ex("incline-walk", "경사 걷기", .cardio, [.cardio], [.legs], usesLoad: false),
    ]

    private static func ex(
        _ id: String, _ name: String, _ equipment: Equipment,
        _ primary: [MuscleGroup], _ secondary: [MuscleGroup], usesLoad: Bool = true
    ) -> Exercise {
        Exercise(id: id, name: name, equipment: equipment,
                 primary: primary, secondary: secondary, usesLoad: usesLoad)
    }

    private static let byID: [String: Exercise] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func find(_ id: String) -> Exercise? { byID[id] }

    static func search(_ query: String) -> [Exercise] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.id.localizedCaseInsensitiveContains(q)
                || $0.equipment.rawValue.contains(q)
                || $0.primary.contains { m in m.rawValue.contains(q) }
        }
    }

    static func grouped(by group: MuscleGroup) -> [Exercise] {
        all.filter { $0.primary.contains(group) }
    }
}
