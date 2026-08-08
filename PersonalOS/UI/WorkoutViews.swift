import SwiftUI
import SwiftData

// MARK: - 운동 기록 화면
//
// 세트 단위로 직접 찍는 화면. HealthKit 이 세트를 주지 않으므로 부하 계산에
// 필요한 데이터는 전부 여기서 나온다.

struct WorkoutListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \POSWorkoutSession.startedAt, order: .reverse) private var sessions: [POSWorkoutSession]
    @ObservedObject private var health = HealthKitService.shared

    @State private var activeSession: POSWorkoutSession?
    @State private var importMessage: String?

    private var openSession: POSWorkoutSession? {
        sessions.first { $0.endedAt == nil }
    }

    var body: some View {
        List {
            Section {
                if let open = openSession {
                    Button {
                        activeSession = open
                    } label: {
                        HStack {
                            Label("진행 중인 운동 이어하기", systemImage: "figure.run")
                            Spacer()
                            Text(open.startedAt.formatted(date: .omitted, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        start()
                    } label: {
                        Label("운동 시작", systemImage: "plus.circle.fill")
                            .font(Theme.body().bold())
                    }
                    .buttonStyle(.plain)
                }

                NavigationLink {
                    MuscleStatusView()
                } label: {
                    Label("근육 상태", systemImage: "heart.text.square")
                }
            }
            .posRow()


            Section("기록") {
                if sessions.isEmpty {
                    Text("아직 기록이 없어요.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sessions) { session in
                    Button {
                        activeSession = session
                    } label: {
                        sessionRow(session)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: delete)
            }
            .posRow()
        }
        .posList()
        .navigationTitle("운동")
        .toolbar {
            if HealthKitService.isAvailable {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await importFromHealth() }
                    } label: {
                        Label("유산소 가져오기", systemImage: "heart.fill")
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let importMessage {
                Text(importMessage)
                    .font(Theme.caption())
                    .padding(.horizontal, Theme.spacingM)
                    .padding(.vertical, Theme.spacingS)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, Theme.spacingM)
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        withAnimation { self.importMessage = nil }
                    }
            }
        }
        .sheet(item: $activeSession) { session in
            WorkoutSessionView(session: session)
        }
        .task { health.refreshAuthorizationState() }
    }

    private func sessionRow(_ session: POSWorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(session.startedAt.formatted(.dateTime.month().day().weekday(.abbreviated)))
                    .font(Theme.body().bold())
                Spacer()
                if session.endedAt == nil {
                    Text("진행 중")
                        .font(Theme.caption2().bold())
                        .foregroundStyle(.orange)
                } else if session.totalSets > 0 {
                    Text("\(session.totalSets)세트")
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            let groups = session.involvedGroups
            if !groups.isEmpty {
                HStack(spacing: Theme.spacingXS) {
                    ForEach(groups) { group in
                        Text(group.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.glassTrack, in: Capsule())
                    }
                }
            }
            let summary = session.setSummary
            if !summary.isEmpty {
                Text(summary)
                    .font(Theme.caption())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func start() {
        let session = POSWorkoutSession()
        context.insert(session)
        try? context.save()
        activeSession = session
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(sessions[index])
        }
        try? context.save()
    }

    private func importFromHealth() async {
        if !health.isAuthorized {
            await health.requestAuthorization()
        }
        let workouts = await health.recentWorkouts()
        let added = WorkoutStore.importFromHealth(workouts, context: context)
        withAnimation {
            importMessage = added > 0 ? "유산소 \(added)개 가져왔어요." : "새로 가져올 유산소 기록이 없어요."
        }
    }
}

// MARK: - 세션 기록

struct WorkoutSessionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: POSWorkoutSession

    @State private var showingPicker = false
    @State private var lastSetAt: Date?

    /// 종목별로 묶되 처음 등장한 순서를 유지한다.
    private var exerciseOrder: [String] {
        var seen: [String] = []
        for set in session.orderedSets where !seen.contains(set.exerciseID) {
            seen.append(set.exerciseID)
        }
        return seen
    }

    var body: some View {
        NavigationStack {
            List {
                if session.totalSets == 0 && session.manualGroups.isEmpty {
                    Section {
                        Text("아래 ‘종목 추가’로 시작하세요.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let lastSetAt, session.endedAt == nil {
                    Section {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let elapsed = Int(context.date.timeIntervalSince(lastSetAt))
                            HStack {
                                Label("마지막 세트 이후", systemImage: "timer")
                                Spacer()
                                Text(String(format: "%d:%02d", elapsed / 60, elapsed % 60))
                                    .font(.title3.monospacedDigit().bold())
                                    .foregroundStyle(elapsed >= 90 ? .green : .primary)
                            }
                        }
                    } footer: {
                        Text("90초가 지나면 초록으로 바뀌어요.")
                    }
                }

                ForEach(exerciseOrder, id: \.self) { exerciseID in
                    exerciseSection(exerciseID)
                }

                if !session.manualGroups.isEmpty {
                    Section("부위 (세트 없이 기록)") {
                        Text(session.manualGroups.map(\.rawValue).joined(separator: " · "))
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        showingPicker = true
                    } label: {
                        Label("종목 추가", systemImage: "plus")
                    }
                }
            }
            .posForm()
            .navigationTitle(session.startedAt.formatted(.dateTime.month().day()))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(session.endedAt == nil ? "운동 완료" : "저장") {
                        Task { await finish() }
                    }
                    .bold()
                }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView { exercise in
                    add(exercise)
                }
            }
        }
    }

    @ViewBuilder
    private func exerciseSection(_ exerciseID: String) -> some View {
        let rows = session.orderedSets.filter { $0.exerciseID == exerciseID }
        let exercise = ExerciseCatalog.find(exerciseID)

        Section {
            ForEach(rows) { set in
                SetRow(set: set, usesLoad: exercise?.usesLoad ?? true)
            }
            .onDelete { offsets in
                for index in offsets { context.delete(rows[index]) }
                try? context.save()
            }

            Button {
                addSet(copying: rows.last, exerciseID: exerciseID)
            } label: {
                Label("세트 추가", systemImage: "plus.circle")
                    .font(Theme.caption())
            }
        } header: {
            HStack {
                Text(exercise?.name ?? exerciseID)
                Spacer()
                Text(exercise?.muscleSummary ?? "")
                    .font(Theme.caption2())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func add(_ exercise: Exercise) {
        addSet(copying: nil, exerciseID: exercise.id)
    }

    private func addSet(copying previous: POSWorkoutSet?, exerciseID: String) {
        let nextOrder = (session.orderedSets.last?.order ?? -1) + 1
        let set = POSWorkoutSet(
            exerciseID: exerciseID,
            weight: previous?.weight ?? 0,
            reps: previous?.reps ?? 10,
            order: nextOrder
        )
        set.session = session
        context.insert(set)
        try? context.save()
        lastSetAt = .now
    }

    private func finish() async {
        if session.endedAt == nil { session.endedAt = .now }
        try? context.save()
        _ = await HealthKitService.shared.save(session: session)
        WorkoutStore.syncToNotion(session, context: context)
        dismiss()
    }
}

/// 세트 한 줄 — 무게/횟수 인라인 편집.
private struct SetRow: View {
    @Environment(\.modelContext) private var context
    @Bindable var set: POSWorkoutSet
    let usesLoad: Bool

    var body: some View {
        HStack(spacing: Theme.spacingS) {
            Button {
                set.isWarmup.toggle()
                try? context.save()
            } label: {
                Text(set.isWarmup ? "W" : "\(set.order + 1)")
                    .font(.caption.bold())
                    .foregroundStyle(set.isWarmup ? .orange : .secondary)
                    .frame(width: 22)
            }
            .buttonStyle(.plain)

            // `value:format:` 를 쓰면 포맷터 왕복 때문에 135.5 처럼 소숫점
            // 있는 무게를 못 넣는다 — NumberField.swift 위쪽 설명 참고.
            if usesLoad {
                PosNumberField(placeholder: "무게", value: set.weight == 0 ? nil : set.weight) { newValue in
                    set.weight = newValue ?? 0
                    try? context.save()
                }
                .frame(maxWidth: 70)
                Text("lb").font(Theme.caption()).foregroundStyle(.secondary)
                Text("×").foregroundStyle(.tertiary)
            }

            PosNumberField(
                placeholder: "횟수",
                value: set.reps == 0 ? nil : Double(set.reps),
                allowsDecimal: false
            ) { newValue in
                set.reps = Int(newValue ?? 0)
                try? context.save()
            }
            .frame(maxWidth: 50)
            Text("회").font(Theme.caption()).foregroundStyle(.secondary)

            Spacer()
        }
    }
}

// MARK: - 종목 고르기

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (Exercise) -> Void

    @State private var query = ""
    @State private var group: MuscleGroup?

    private var results: [Exercise] {
        var list = ExerciseCatalog.search(query)
        if let group { list = list.filter { $0.primary.contains(group) } }
        return list
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.spacingXS) {
                            chip("전체", isOn: group == nil) { group = nil }
                            ForEach(MuscleGroup.allCases) { candidate in
                                chip(candidate.rawValue, isOn: group == candidate) {
                                    group = (group == candidate) ? nil : candidate
                                }
                            }
                        }
                    }
                }

                ForEach(results) { exercise in
                    Button {
                        onPick(exercise)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                            HStack(spacing: 6) {
                                Text(exercise.equipment.rawValue)
                                Text("·")
                                Text(exercise.muscleSummary)
                            }
                            .font(Theme.caption2())
                            .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $query, prompt: "종목 검색")
            .navigationTitle("종목 (\(results.count))")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
        }
    }

    private func chip(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn ? Color.primary : .secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(isOn ? AnyShapeStyle(Theme.glassInk.opacity(0.15)) : AnyShapeStyle(Theme.glassTrack), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
