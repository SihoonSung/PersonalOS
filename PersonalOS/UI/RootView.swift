import SwiftUI
import SwiftData

/// Navigation routes from the dashboard root.
enum Route: Hashable {
    case workout
    case databases
    case database(POSDatabase)
    case recurring(POSDatabase)
    case settings
}

/// Root: 대시보드가 메인 화면. 좌상단 → 데이터베이스 목록, 우상단 → 설정.
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \POSDatabase.sortIndex) private var databases: [POSDatabase]
    @State private var path: [Route] = []
    @State private var capture: (scan: ReceiptScan, data: Data?)?

    private var budgetDatabase: POSDatabase? {
        databases.first { $0.templateKey == TemplateKey.budget }
    }

    var body: some View {
        NavigationStack(path: $path) {
            DashboardView(
                openDatabase: { path.append(.database($0)) },
                onOpenDatabases: { path.append(.databases) },
                onOpenSettings: { path.append(.settings) },
                onOpenRecurring: { path.append(.recurring($0)) },
                onOpenWorkout: { path.append(.workout) }
            )
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .workout:
                    WorkoutListView()
                case .databases:
                    DatabaseListView(openDatabase: { path.append(.database($0)) })
                case .database(let db):
                    DatabaseView(database: db)
                        .id(db.uuid)
                case .recurring(let db):
                    RecurringView(database: db)
                        .id(db.uuid)
                case .settings:
                    SettingsView()
                }
            }
        }
        // 공유 시트에서 넘어온 스크린샷 — 인텐트가 앱 그룹에 적어두고 앱을 연다.
        // 활성화될 때마다 확인하되 `take()`가 한 번만 꺼내므로 반복해서 안 뜬다.
        .task { pickUpCapture() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { pickUpCapture() }
        }
        // 공유 익스텐션이 personalos://capture 로 앱을 연다. scenePhase 로도
        // 잡히지만, 이미 떠 있던 앱으로 돌아오는 경우까지 확실히 하려고 둔다.
        .onOpenURL { _ in pickUpCapture() }
        .sheet(isPresented: Binding(get: { capture != nil }, set: { if !$0 { capture = nil } })) {
            if let capture, let budget = budgetDatabase {
                CaptureReviewSheet(database: budget, scan: capture.scan, imageData: capture.data)
            }
        }
    }

    private func pickUpCapture() {
        guard capture == nil, budgetDatabase != nil, let pending = PendingCapture.take() else { return }
        capture = (pending.scan, pending.imageData)
    }
}

/// 데이터베이스 목록 (구 사이드바) — 생성/삭제 지원.
struct DatabaseListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \POSDatabase.sortIndex) private var databases: [POSDatabase]
    var openDatabase: (POSDatabase) -> Void

    @State private var showingNewDatabase = false
    @State private var newDatabaseName = ""

    var body: some View {
        List {
            Section("데이터베이스") {
                ForEach(databases) { db in
                    Button {
                        openDatabase(db)
                    } label: {
                        HStack {
                            Label {
                                Text(db.name)
                                    .foregroundStyle(.primary)
                            } icon: {
                                Text(db.icon)
                            }
                            Spacer()
                            Text("\(db.entryCount)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .contextMenu {
                        Button("삭제", role: .destructive) { delete(db) }
                    }
                    .posRow()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(DashboardBackground())
        .navigationTitle("데이터베이스")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingNewDatabase = true
                    } label: {
                        Label("빈 데이터베이스", systemImage: "square.dashed")
                    }
                    Section("템플릿") {
                        // 함수를 값으로 넘기면 MainActor 격리가 벗겨져 경고가 난다.
                        // 클로저로 감싸면 호출이 MainActor 안에서 일어난다.
                        Button("📏 신체 기록") { createFromTemplate { Templates.makeBodyLog(sortIndex: $0) } }
                        Button("📒 표현 노트") { createFromTemplate { Templates.makeExpressions(sortIndex: $0) } }
                        Button("🏋️ 운동 기록") { createFromTemplate { Templates.makeWorkout(sortIndex: $0) } }
                        Button("✅ Tasks (노션)") { createFromTemplate { Templates.makeNotionTasks(sortIndex: $0) } }
                        Button("📖 말씀 기록") { createFromTemplate { Templates.makeSermon(sortIndex: $0) } }
                    }
                } label: {
                    Label("새 데이터베이스", systemImage: "plus")
                }
            }
        }
        .alert("새 데이터베이스", isPresented: $showingNewDatabase) {
            TextField("이름", text: $newDatabaseName)
            Button("만들기") { createDatabase() }
            Button("취소", role: .cancel) { newDatabaseName = "" }
        } message: {
            Text("빈 데이터베이스를 만들고 속성은 나중에 추가할 수 있어요.")
        }
    }

    private func createDatabase() {
        let name = newDatabaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let nextIndex = (databases.map(\.sortIndex).max() ?? -1) + 1
        let db = Templates.makeBlank(name: name, sortIndex: nextIndex)
        context.insert(db)
        try? context.save()
        newDatabaseName = ""
        openDatabase(db)
    }

    private func createFromTemplate(_ make: (Int) -> POSDatabase) {
        let nextIndex = (databases.map(\.sortIndex).max() ?? -1) + 1
        let db = make(nextIndex)
        context.insert(db)
        try? context.save()
        openDatabase(db)
    }

    private func delete(_ db: POSDatabase) {
        context.delete(db)
        try? context.save()
    }
}
