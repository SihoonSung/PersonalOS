import SwiftUI
import SwiftData

// MARK: - 설정 — 모든 연동·스위치가 모이는 단 하나의 자리
//
// 예전엔 예산 설정은 가계부 안, 헬스 연동은 운동 화면 안, 잔액 기준점은
// 대시보드 카드 안에 흩어져 있었다. "그 화면에서 바로" 를 노린 배치였지만
// 결국 어디서 뭘 바꾸는지 알 수 없게 됐다. 전부 여기로 모은다.

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \POSDatabase.sortIndex) private var databases: [POSDatabase]

    @ObservedObject private var ai = AIService.shared
    @ObservedObject private var notion = NotionSyncService.shared
    @ObservedObject private var health = HealthKitService.shared
    private let mail = MailSyncService.shared

    @AppStorage(AppSettings.mcpEnabledKey) private var mcpEnabled = false
    @AppStorage(AppSettings.mcpPortKey) private var mcpPort = 4141
    @AppStorage(AppLock.enabledKey) private var appLockEnabled = false
    @AppStorage(AmountPrivacy.key) private var hideAmounts = false
    @AppStorage("monthlyBudget") private var monthlyBudget: Double = 0

    @State private var showingMailSettings = false
    @State private var showingCaptureGuide = false
    @State private var showingNotionSettings = false
    @State private var showingBalanceEditor = false
    @State private var showingBudgetEditor = false
    @State private var budgetInput = ""

    private var budgetDatabase: POSDatabase? {
        databases.first { $0.templateKey == TemplateKey.budget }
    }

    private var linkedNotionCount: Int {
        databases.filter { $0.notionSyncEnabled && $0.notionDatabaseID != nil }.count
    }

    private func unreviewedCount(in database: POSDatabase) -> Int {
        guard let reviewed = database.reviewedProperty else { return 0 }
        return (database.entries ?? []).filter { $0.sourceKind == "email" && !$0.bool(for: reviewed) }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingL) {
                moneySection
                connectionsSection
                privacySection
                dataSection
                aboutSection
                Spacer(minLength: Theme.spacingXL)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.spacingM)
        }
        .posScreen()
        .navigationTitle("설정")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showingMailSettings) { MailSettingsView() }
        .sheet(isPresented: $showingNotionSettings) { NotionSettingsView() }
        .sheet(isPresented: $showingCaptureGuide) { CaptureGuideView() }
        .sheet(isPresented: $showingBalanceEditor) {
            if let budget = budgetDatabase { BalanceEditorView(database: budget) }
        }
        .alert("월 예산", isPresented: $showingBudgetEditor) {
            TextField("예: 3000", text: $budgetInput)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Button("저장") {
                monthlyBudget = Double(budgetInput.replacingOccurrences(of: ",", with: "")) ?? 0
                budgetInput = ""
            }
            if monthlyBudget > 0 {
                Button("예산 해제", role: .destructive) { monthlyBudget = 0 }
            }
            Button("취소", role: .cancel) { budgetInput = "" }
        } message: {
            Text("한 달 지출 목표를 정하면 남은 예산과 사용률을 보여줘요.")
        }
        .task { health.refreshAuthorizationState() }
    }

    // MARK: 돈

    /// 이번 달 받은 정산이 있으면 예산이 그만큼 올라간 걸 여기서 알려준다.
    /// 숫자가 왜 늘었는지 설명 없이 늘어나면 오히려 안 믿게 된다.
    private func budgetSubtitle(_ database: POSDatabase) -> String? {
        guard monthlyBudget > 0 else { return nil }
        let settled = BudgetMath.settledIn(in: database, month: .now)
        guard settled > 0 else { return nil }
        let effective = monthlyBudget + settled
        return "받은 정산 \(database.formattedAmount(settled)) 만큼 올라가 이번 달은 \(database.formattedAmount(effective))"
    }

    @ViewBuilder
    private var moneySection: some View {
        if let budget = budgetDatabase {
            GlassSection("돈") {
                Button {
                    budgetInput = monthlyBudget > 0 ? String(Int(monthlyBudget)) : ""
                    showingBudgetEditor = true
                } label: {
                    PosRow("월 예산", systemImage: "target",
                           subtitle: budgetSubtitle(budget), showsChevron: true) {
                        Text(monthlyBudget > 0 ? budget.formattedAmount(monthlyBudget) : "없음")
                            .font(Theme.caption())
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .buttonStyle(.plain)

                PosDivider()

                Button {
                    showingBalanceEditor = true
                } label: {
                    PosRow("계좌 잔액 기준점", systemImage: "banknote",
                           subtitle: "지금 잔고를 한 번 알려주면 이후 거래로 자동 계산해요",
                           showsChevron: true) {
                        EmptyView()
                    }
                }
                .buttonStyle(.plain)

                PosDivider()

                NavigationLink {
                    RecurringView(database: budget)
                } label: {
                    PosRow("고정지출", systemImage: "arrow.trianglehead.2.clockwise",
                           subtitle: "거래에서 자동으로 찾아낸 정기 결제", showsChevron: true) {
                        EmptyView()
                    }
                }
                .buttonStyle(.plain)

                PosDivider()

                NavigationLink {
                    ReviewQueueView(database: budget)
                } label: {
                    PosRow("검토 대기", systemImage: "tray.full", showsChevron: true) {
                        let count = unreviewedCount(in: budget)
                        if count > 0 { PosPill("\(count)건", tint: .orange) }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 연동

    private var connectionsSection: some View {
        GlassSection("연동", footnote: "메일은 읽기만 하고 건드리지 않아요. 노션을 연결하지 않으면 이 기기와 iCloud에만 저장됩니다.") {
            Button {
                showingMailSettings = true
            } label: {
                PosRow("메일 가계부", systemImage: "envelope.arrow.triangle.branch",
                       subtitle: "Chase 알림을 읽어 가계부에 자동으로 넣어요", showsChevron: true) {
                    PosPill(MailSettings.isConfigured ? "켜짐" : "꺼짐",
                            tint: MailSettings.isConfigured ? .green : nil)
                }
            }
            .buttonStyle(.plain)

            if MailSettings.isConfigured {
                PosDivider()
                Button {
                    Task { await mail.syncNow() }
                } label: {
                    PosRow("지금 가져오기", systemImage: "arrow.down.circle",
                           subtitle: mail.lastResult?.summary) {
                        if mail.isSyncing {
                            Text(mail.progressText)
                                .font(Theme.caption2())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(mail.isSyncing)
            }

            PosDivider()

            Button {
                showingCaptureGuide = true
            } label: {
                PosRow("스크린샷으로 기록", systemImage: "text.viewfinder",
                       subtitle: "송금 완료 화면을 공유하면 금액과 상대를 읽어 채워요",
                       showsChevron: true) { EmptyView() }
            }
            .buttonStyle(.plain)

            PosDivider()

            Button {
                showingNotionSettings = true
            } label: {
                PosRow("Notion", systemImage: "arrow.triangle.2.circlepath",
                       subtitle: notionSubtitle, showsChevron: true) {
                    PosPill(linkedNotionCount > 0 ? "\(linkedNotionCount)개" : "꺼짐",
                            tint: notionTint)
                }
            }
            .buttonStyle(.plain)

            PosDivider()

            healthRow

            #if os(macOS)
            PosDivider()
            Toggle(isOn: $mcpEnabled) {
                PosRow("MCP 서버", systemImage: "terminal",
                       subtitle: mcpEnabled ? "http://127.0.0.1:\(mcpPort)/mcp" : "AI 에이전트가 데이터를 읽고 쓸 수 있게 해요") {
                    EmptyView()
                }
            }
            .onChange(of: mcpEnabled) {
                if mcpEnabled { MCPServer.shared.start(port: mcpPort) } else { MCPServer.shared.stop() }
            }
            #endif
        }
    }

    private var notionSubtitle: String? {
        if let error = notion.lastError, !error.isEmpty { return error }
        if let at = notion.lastSyncAt {
            return "마지막 동기화 \(at.formatted(.relative(presentation: .named)))"
        }
        return linkedNotionCount > 0 ? "아직 동기화되지 않았어요" : "데이터베이스별로 양방향 동기화"
    }

    private var notionTint: Color? {
        if let error = notion.lastError, !error.isEmpty { return .red }
        return linkedNotionCount > 0 ? .green : nil
    }

    @ViewBuilder
    private var healthRow: some View {
        if HealthKitService.isAvailable {
            Button {
                Task { await health.requestAuthorization() }
            } label: {
                PosRow("애플 헬스", systemImage: "heart.fill",
                       subtitle: "유산소 기록을 가져와요. 웨이트는 앱에서 세트로 기록합니다") {
                    PosPill(health.isAuthorized ? "연결됨" : "연결하기",
                            tint: health.isAuthorized ? .green : nil)
                }
            }
            .buttonStyle(.plain)
        } else {
            PosRow("애플 헬스", systemImage: "heart.fill",
                   subtitle: "이 기기에서는 건강 데이터를 쓸 수 없어요") { EmptyView() }
        }
    }

    // MARK: 보안 · 표시

    private var privacySection: some View {
        GlassSection("보안 · 표시", footnote: privacyFootnote) {
            Toggle(isOn: $hideAmounts) {
                PosRow("금액 가리기", systemImage: hideAmounts ? "eye.slash" : "eye",
                       subtitle: "잔액과 지출을 ••••로 가려요. 카드의 눈 버튼으로도 바꿀 수 있어요") {
                    EmptyView()
                }
            }

            PosDivider()

            Toggle(isOn: $appLockEnabled) {
                PosRow("앱 잠금", systemImage: "faceid",
                       subtitle: AppLock.isAvailable ? "열 때 \(AppLock.biometryName)로 확인해요" : "기기에 잠금 암호가 없어요") {
                    EmptyView()
                }
            }
            .disabled(!AppLock.isAvailable)
            .onChange(of: appLockEnabled) {
                AppLock.isEnabled = appLockEnabled
                if appLockEnabled { AppLock.shared.lockNow() }
            }
        }
    }

    private var privacyFootnote: String? {
        AppLock.isAvailable ? "잠깐 다른 앱에 다녀오는 정도(1분 이내)로는 다시 묻지 않습니다." : nil
    }

    // MARK: 데이터

    private var dataSection: some View {
        GlassSection("데이터", footnote: "iCloud에 로그인돼 있으면 아이폰↔맥이 자동으로 동기화됩니다.") {
            ForEach(Array(databases.enumerated()), id: \.element.uuid) { index, db in
                if index > 0 { PosDivider() }
                NavigationLink {
                    ExportDatabaseView(database: db)
                } label: {
                    PosRow("\(db.icon) \(db.name)", subtitle: "JSON으로 내보내기", showsChevron: true) {
                        Text("\(db.entryCount)")
                            .font(Theme.caption())
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 정보

    private var aboutSection: some View {
        GlassSection("앱") {
            PosRow("온디바이스 AI", systemImage: "sparkles",
                   subtitle: ai.isAvailable ? nil : "사용할 수 없어 규칙 기반 파싱을 씁니다") {
                PosPill(ai.isAvailable ? "사용 가능" : "사용 불가", tint: ai.isAvailable ? .green : nil)
            }
            PosDivider()
            PosRow("버전") {
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .font(Theme.caption())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - 내보내기

/// 직렬화는 항목×속성이라 비싸다. 설정 목록은 동기화 진행마다 다시 그려지므로
/// 인라인으로 만들지 않고 이 화면에서 필요할 때만 만든다.
private struct ExportDatabaseView: View {
    let database: POSDatabase
    @State private var payload: String?

    var body: some View {
        Group {
            if let payload {
                ScrollView {
                    VStack(spacing: Theme.spacingM) {
                        ShareLink(item: payload, preview: SharePreview("\(database.name).json")) {
                            Label("JSON 내보내기", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Theme.spacingS)
                        }
                        .buttonStyle(.borderedProminent)

                        Text(payload.prefix(4000))
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCardStyle()
                    }
                    .padding(Theme.spacingM)
                }
            } else {
                ProgressView()
            }
        }
        .posScreen()
        .navigationTitle("\(database.icon) \(database.name)")
        .task { payload = ExportService.json(for: database) }
    }
}

enum ExportService {

    /// 전체 데이터베이스(스키마 + 항목)를 보기 좋은 JSON으로 — MCP 말고도
    /// "다른 앱이 읽을 수 있다"는 탈출구.
    @MainActor
    static func json(for db: POSDatabase) -> String {
        var payload: [String: Any] = [
            "database": db.name,
            "template_key": db.templateKey,
            "exported_at": ISO8601DateFormatter().string(from: .now),
        ]
        payload["schema"] = db.orderedProperties.map { property -> [String: Any] in
            var item: [String: Any] = ["name": property.name, "type": property.type.rawValue]
            if property.type == .select || property.type == .multiSelect {
                item["options"] = property.config.selectOptions
            }
            return item
        }
        payload["entries"] = (db.entries ?? [])
            .sorted { $0.createdAt > $1.createdAt }
            .map { entry -> [String: Any] in
                var item: [String: Any] = [
                    "id": entry.uuid.uuidString,
                    "title": entry.title,
                    "created_at": ISO8601DateFormatter().string(from: entry.createdAt),
                ]
                var values: [String: Any] = [:]
                for property in db.orderedProperties {
                    if let v = entry.jsonValue(for: property) { values[property.name] = v }
                }
                item["values"] = values
                return item
            }

        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
