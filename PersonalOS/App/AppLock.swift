import SwiftUI
import LocalAuthentication
import Observation

// MARK: - 앱 잠금
//
// 가계부·잔액이 들어있으니 남에게 폰을 넘겨줄 때를 대비한 최소한의 방어선.
// 생체인증이 없거나 실패하면 기기 암호로 떨어진다(`deviceOwnerAuthentication`).
//
// 앱을 백그라운드로 보내면 다시 잠그고, 그 전에 화면을 가린다 — 앱 전환기
// 스냅샷에 잔액이 찍히는 걸 막기 위해서다.

@Observable
final class AppLock {

    static let shared = AppLock()

    static let enabledKey = "appLockEnabled"
    /// 잠깐 다른 앱 갔다 오는 정도로는 다시 안 묻는다.
    static let graceSeconds: TimeInterval = 60

    private(set) var isLocked = false
    private(set) var isAuthenticating = false
    private(set) var lastError: String?

    private var backgroundedAt: Date?

    private init() {
        isLocked = AppLock.isEnabled
    }

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if !newValue { shared.unlockWithoutAuth() }
        }
    }

    /// 이 기기에서 생체인증/암호를 쓸 수 있는지.
    static var isAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "기기 암호"
        }
    }

    // MARK: 잠금 흐름

    func lockIfNeeded() {
        guard AppLock.isEnabled else { return }
        backgroundedAt = .now
    }

    /// 포그라운드로 돌아왔을 때 호출. 유예 시간이 지났으면 잠근다.
    func refreshOnForeground() {
        guard AppLock.isEnabled else {
            isLocked = false
            return
        }
        guard let since = backgroundedAt else { return }
        if Date.now.timeIntervalSince(since) >= AppLock.graceSeconds {
            isLocked = true
        }
        backgroundedAt = nil
    }

    func lockNow() {
        guard AppLock.isEnabled else { return }
        isLocked = true
    }

    private func unlockWithoutAuth() {
        isLocked = false
        backgroundedAt = nil
        lastError = nil
    }

    func authenticate() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        lastError = nil
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedCancelTitle = "취소"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // 기기에 암호조차 없으면 잠글 방법이 없다 — 막아두면 앱을 영영
            // 못 여는 상태가 되므로 그냥 통과시킨다.
            unlockWithoutAuth()
            return
        }

        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "PersonalOS를 열려면 인증이 필요해요"
            )
            if ok { unlockWithoutAuth() }
        } catch {
            lastError = (error as? LAError).map(Self.message(for:)) ?? error.localizedDescription
        }
    }

    private static func message(for error: LAError) -> String {
        switch error.code {
        case .userCancel, .appCancel, .systemCancel: return ""
        case .biometryLockout: return "생체인증이 잠겼어요. 기기 암호로 열어 주세요."
        case .authenticationFailed: return "인증에 실패했어요. 다시 시도해 주세요."
        default: return error.localizedDescription
        }
    }
}

// MARK: - 잠금 화면

/// 앱 전체를 감싸서, 잠겨 있으면 내용을 가리고 인증 화면을 띄운다.
struct LockGate<Content: View>: View {
    @ViewBuilder var content: Content

    // `private let`이어야 한다. 프로퍼티 래퍼가 없는 `private var`는 구조체의
    // memberwise 이니셜라이저까지 private으로 끌어내려서, 다른 파일에서
    // `LockGate { ... }`를 만들 수 없게 된다. `let`은 이니셜라이저 파라미터에
    // 아예 포함되지 않아 접근 수준에 영향이 없다.
    private let lock = AppLock.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            content
                // 잠긴 동안은 물론이고, 백그라운드로 나가는 순간에도 가린다.
                // 앱 전환기 스냅샷에 잔액이 찍히면 잠금이 무의미해진다.
                .blur(radius: shouldObscure ? 24 : 0)
                .allowsHitTesting(!lock.isLocked)

            if lock.isLocked {
                lockScreen
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: lock.isLocked)
        .task(id: lock.isLocked) {
            if lock.isLocked { await lock.authenticate() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: lock.lockIfNeeded()
            case .active: lock.refreshOnForeground()
            default: break
            }
        }
    }

    private var shouldObscure: Bool {
        lock.isLocked || scenePhase != .active
    }

    private var lockScreen: some View {
        VStack(spacing: Theme.spacingM) {
            Image(systemName: "lock.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)

            Text("잠겨 있어요")
                .font(Theme.title())

            if let error = lock.lastError, !error.isEmpty {
                Text(error)
                    .font(Theme.caption())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.spacingL)
            }

            Button {
                Task { await lock.authenticate() }
            } label: {
                Label("\(AppLock.biometryName)로 열기", systemImage: "faceid")
            }
            .buttonStyle(.borderedProminent)
            .disabled(lock.isAuthenticating)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .ignoresSafeArea()
    }
}
