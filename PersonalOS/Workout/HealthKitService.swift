import Foundation
import Combine
#if canImport(HealthKit)
import HealthKit
#endif

// MARK: - 애플 헬스 연동
//
// 알아둘 한계: HealthKit 은 근력 운동의 **세트·무게·횟수를 주지 않는다.**
// 워크아웃 종류·시간·칼로리까지다. 그래서 역할을 이렇게 나눈다:
//   읽기 — **유산소만** 가져온다. 웨이트는 앱에서 세트로 찍으므로 헬스에서
//          가져와 봐야 부위도 강도도 알 수 없는 빈 세션만 쌓인다.
//   쓰기 — 앱에서 기록한 세션을 헬스에 남겨 링 활동/타 앱과 공유
//   체중 — 신체 기록 템플릿에 채워 넣을 최신 체중
//
// 세트 데이터는 앱이 원본이다 (사용자가 앱을 데이터 주인으로 정했다).

/// 헬스에서 읽어온 세션 — 아직 앱 모델로 만들기 전 단계.
struct ImportedWorkout: Identifiable {
    let id: String            // HKWorkout UUID
    let start: Date
    let end: Date
    let activityName: String
    let groups: [MuscleGroup]
    let energyKcal: Double?

    var durationMinutes: Double { end.timeIntervalSince(start) / 60 }
}

@MainActor
final class HealthKitService: ObservableObject {

    static let shared = HealthKitService()

    @Published private(set) var isAuthorized = false
    @Published private(set) var lastError: String?

    private init() {}

    #if canImport(HealthKit)
    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let mass = HKObjectType.quantityType(forIdentifier: .bodyMass) { types.insert(mass) }
        if let fat = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage) { types.insert(fat) }
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        return types
    }

    private var writeTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        return types
    }

    func requestAuthorization() async {
        guard Self.isAvailable else {
            lastError = "이 기기에서는 건강 데이터를 쓸 수 없어요."
            return
        }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            // 읽기 권한은 조회해도 알 수 없다(개인정보 보호). 쓰기 권한으로만 판단.
            isAuthorized = store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshAuthorizationState() {
        guard Self.isAvailable else { return }
        isAuthorized = store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    // MARK: 읽기

    /// 최근 N일의 **유산소** 워크아웃. 웨이트/요가 등은 건너뛴다.
    /// 앱이 직접 써 넣은 것도 제외한다(그대로 되읽으면 중복).
    func recentWorkouts(days: Int = 14) async -> [ImportedWorkout] {
        guard Self.isAvailable else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let samples: [HKSample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, result, _ in
                continuation.resume(returning: result ?? [])
            }
            store.execute(query)
        }

        let bundleID = Bundle.main.bundleIdentifier
        return samples.compactMap { sample -> ImportedWorkout? in
            guard let workout = sample as? HKWorkout else { return nil }
            // 우리가 쓴 샘플은 건너뛴다.
            if let bundleID, workout.sourceRevision.source.bundleIdentifier == bundleID { return nil }
            // 유산소만 — 웨이트는 앱에서 세트로 기록한다.
            guard Self.isCardio(workout.workoutActivityType) else { return nil }
            let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie())
            return ImportedWorkout(
                id: workout.uuid.uuidString,
                start: workout.startDate,
                end: workout.endDate,
                activityName: Self.name(for: workout.workoutActivityType),
                groups: Self.groups(for: workout.workoutActivityType),
                energyKcal: energy
            )
        }
    }

    /// 최신 체중(lb)과 측정 시각.
    func latestBodyMass() async -> (pounds: Double, date: Date)? {
        guard Self.isAvailable, let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let sample: HKQuantitySample? = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, result, _ in
                continuation.resume(returning: result?.first as? HKQuantitySample)
            }
            store.execute(query)
        }
        guard let sample else { return nil }
        return (sample.quantity.doubleValue(for: .pound()), sample.startDate)
    }

    // MARK: 쓰기

    /// 앱에서 기록한 세션을 헬스에 남긴다. 실패해도 앱 기록은 그대로다.
    func save(session: POSWorkoutSession) async -> Bool {
        guard Self.isAvailable, session.pushedToHealthKit == false else { return false }
        let end = session.endedAt ?? .now
        guard end > session.startedAt else { return false }

        let isCardio = session.involvedGroups == [.cardio]
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = isCardio ? .other : .traditionalStrengthTraining

        do {
            let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
            try await builder.beginCollection(at: session.startedAt)
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
            session.pushedToHealthKit = true
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: 종류 매핑

    /// 가져올 대상인지 — 유산소만 true.
    ///
    /// 웨이트(traditionalStrengthTraining 등)를 넣지 않는 이유: 헬스에는 어느
    /// 부위를 얼마나 했는지가 없어서, 가져와도 부위 불명 세션이 목록만 채운다.
    /// 근력은 앱에서 세트로 기록하는 게 원본이다.
    static func isCardio(_ type: HKWorkoutActivityType) -> Bool {
        switch type {
        case .running, .walking, .cycling, .rowing, .elliptical,
             .stairClimbing, .stairs, .highIntensityIntervalTraining,
             .jumpRope, .swimming, .hiking, .mixedCardio, .crossCountrySkiing,
             .downhillSkiing, .skatingSports, .paddleSports, .surfingSports:
            return true
        default:
            return false
        }
    }

    /// 유산소 세션은 세트가 없으니 부위를 심폐로 잡아 기본 부하(v1 §1의 6점)를
    /// 적용한다.
    static func groups(for type: HKWorkoutActivityType) -> [MuscleGroup] {
        isCardio(type) ? [.cardio] : []
    }

    static func name(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "러닝"
        case .walking: return "걷기"
        case .cycling: return "사이클"
        case .rowing: return "로잉"
        case .elliptical: return "일립티컬"
        case .stairClimbing, .stairs: return "스텝밀"
        case .highIntensityIntervalTraining: return "HIIT"
        case .jumpRope: return "줄넘기"
        case .swimming: return "수영"
        case .hiking: return "하이킹"
        case .coreTraining: return "코어 운동"
        case .yoga: return "요가"
        case .pilates: return "필라테스"
        case .flexibility: return "스트레칭"
        case .traditionalStrengthTraining: return "웨이트"
        case .functionalStrengthTraining: return "기능성 웨이트"
        case .crossTraining: return "크로스 트레이닝"
        default: return "운동"
        }
    }

    #else
    static var isAvailable: Bool { false }
    func requestAuthorization() async { lastError = "이 플랫폼에서는 건강 데이터를 쓸 수 없어요." }
    func refreshAuthorizationState() {}
    func recentWorkouts(days: Int = 14) async -> [ImportedWorkout] { [] }
    func latestBodyMass() async -> (pounds: Double, date: Date)? { nil }
    func save(session: POSWorkoutSession) async -> Bool { false }
    static func isCardio(_ type: Int) -> Bool { false }
    static func groups(for type: Int) -> [MuscleGroup] { [] }
    #endif
}
