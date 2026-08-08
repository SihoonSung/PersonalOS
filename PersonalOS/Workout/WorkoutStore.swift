import Foundation
import SwiftData

// MARK: - 운동 데이터 접근 + 노션 브릿지
//
// 부하 엔진(MuscleLoad)은 SwiftData 를 모르는 순수 함수라, 모델 ↔ 엔진 입력
// 변환을 여기서 한다. 노션 운동 기록 DB로의 요약 푸시도 여기 모아 둔다.

@MainActor
enum WorkoutStore {

    // MARK: 엔진 입력 변환

    static func loggedSessions(_ sessions: [POSWorkoutSession]) -> [LoggedSession] {
        sessions.map { session in
            LoggedSession(
                date: session.startedAt,
                sets: session.orderedSets.map {
                    LoggedSet(exerciseID: $0.exerciseID, weight: $0.weight, reps: $0.reps, isWarmup: $0.isWarmup)
                },
                manualGroups: session.manualGroups
            )
        }
    }

    static func oneRMs(context: ModelContext) -> [String: Double] {
        let records = (try? context.fetch(FetchDescriptor<POSOneRepMax>())) ?? []
        var best: [String: Double] = [:]
        for record in records {
            // 같은 종목이 여럿이면 최신 것을 쓴다.
            if let existing = best[record.exerciseID] {
                best[record.exerciseID] = max(existing, record.weight)
            } else {
                best[record.exerciseID] = record.weight
            }
        }
        return best
    }

    /// 지금 시점의 부위별 상태. 감쇠가 가장 긴 부위(72h)의 3배까지만 읽으면
    /// 충분해서 최근 10일로 자른다.
    static func states(context: ModelContext, now: Date = .now) -> [MuscleState] {
        let since = now.addingTimeInterval(-10 * 24 * 3600)
        var descriptor = FetchDescriptor<POSWorkoutSession>(
            predicate: #Predicate { $0.startedAt >= since },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        let sessions = (try? context.fetch(descriptor)) ?? []
        return MuscleLoad.states(
            sessions: loggedSessions(sessions),
            oneRMs: oneRMs(context: context),
            now: now
        )
    }

    static func recentSessions(context: ModelContext, limit: Int = 30) -> [POSWorkoutSession] {
        var descriptor = FetchDescriptor<POSWorkoutSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: 애플 헬스에서 가져오기

    /// 이미 있는 세션은 건너뛴다 (healthKitUUID 가 중복 방지 키).
    static func importFromHealth(_ workouts: [ImportedWorkout], context: ModelContext) -> Int {
        let existing = Set(
            ((try? context.fetch(FetchDescriptor<POSWorkoutSession>())) ?? [])
                .compactMap(\.healthKitUUID)
        )
        var added = 0
        for workout in workouts where !existing.contains(workout.id) {
            let session = POSWorkoutSession(startedAt: workout.start)
            session.endedAt = workout.end
            session.healthKitUUID = workout.id
            session.durationMinutes = workout.durationMinutes
            session.manualGroups = workout.groups
            session.note = workout.activityName
            context.insert(session)
            added += 1
        }
        if added > 0 { try? context.save() }
        return added
    }

    // MARK: 노션 운동 기록 DB로 요약 푸시

    /// 세션을 노션 운동 기록 DB의 항목 하나로 반영한다.
    /// 부위는 multi_select, 세트 요약은 메모 — 밤 루틴이 읽던 형식과 같다.
    static func syncToNotion(_ session: POSWorkoutSession, context: ModelContext) {
        let databases = (try? context.fetch(FetchDescriptor<POSDatabase>())) ?? []
        guard let workoutDB = databases.first(where: { $0.templateKey == TemplateKey.workout }) else { return }

        let entry: POSEntry
        if let uuid = session.notionEntryUUID,
           let existing = (workoutDB.entries ?? []).first(where: { $0.uuid == uuid }) {
            entry = existing
        } else {
            entry = POSEntry()
            entry.database = workoutDB
            context.insert(entry)
            session.notionEntryUUID = entry.uuid
        }

        let groups = session.involvedGroups
        entry.title = title(for: session, groups: groups)

        if let property = workoutDB.dateProperty {
            entry.setDate(session.startedAt, for: property, context: context)
        }
        if let property = workoutDB.orderedProperties.first(where: { $0.type == .multiSelect }) {
            entry.setTextList(groups.map(\.rawValue), for: property, context: context)
        }
        if let property = workoutDB.orderedProperties.first(where: { $0.name == "유형" && $0.type == .select }) {
            entry.setText(kindLabel(for: groups), for: property, context: context)
        }
        if let property = workoutDB.orderedProperties.first(where: { $0.name == "메모" }) {
            let summary = session.setSummary
            let text = summary.isEmpty
                ? "\(session.note) \(Int(session.durationMinutes))분".trimmingCharacters(in: .whitespaces)
                : summary
            entry.setText(text, for: property, context: context)
        }
        // "분석됨" — 앱이 이미 부하를 계산했다는 표시. 밤 루틴이 중복 계산하지 않게.
        if let property = workoutDB.orderedProperties.first(where: { $0.name == "분석됨" && $0.type == .checkbox }) {
            entry.setBool(true, for: property, context: context)
        }

        try? context.save()
        NotionSyncService.shared.scheduleAutoSync()
    }

    private static func title(for session: POSWorkoutSession, groups: [MuscleGroup]) -> String {
        if !session.note.isEmpty && session.totalSets == 0 { return session.note }
        let names = groups.filter { $0 != .cardio }.map(\.rawValue)
        if names.isEmpty { return groups.isEmpty ? "운동" : groups.map(\.rawValue).joined(separator: " · ") }
        return names.joined(separator: " · ")
    }

    private static func kindLabel(for groups: [MuscleGroup]) -> String {
        let hasCardio = groups.contains(.cardio)
        let hasWeights = groups.contains { $0 != .cardio }
        if hasCardio && hasWeights { return "혼합" }
        if hasCardio { return "유산소" }
        return "웨이트"
    }
}
