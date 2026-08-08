import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - PersonalOS 디자인 시스템
//
// 화면마다 List/Form/유리카드를 제각각 쓰다 보니 같은 앱처럼 보이지 않았다.
// 여기서 **한 벌의 어휘**를 정의하고 모든 화면이 이것만 쓴다.
//
// 규칙 (대시보드에서 뽑아낸 것):
//   1. 바탕은 항상 웜 그라디언트 + 블롭. 리스트/폼의 기본 배경은 지운다.
//   2. 내용은 유리 표면 위에 올린다. 모서리 반경은 한 종류(20).
//   3. 섹션 제목은 caption bold secondary — 카드 밖이든 안이든 같다.
//   4. 색은 의미가 있을 때만. 기본은 잉크 톤(모노크롬).
//   5. 숫자는 monospacedDigit, 큰 숫자는 rounded.

// MARK: 화면 바탕

extension View {

    /// 스크롤/리스트 화면의 공통 바탕. 모든 최상위 화면에 붙인다.
    /// 키보드 내리는 수단도 여기서 같이 붙는다 — 화면마다 빼먹지 않도록.
    func posScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(DashboardBackground())
            .posKeyboardDismissable()
    }

    /// 리스트 기반 화면 — 스타일·간격·바탕을 한 번에 맞춘다.
    func posList() -> some View {
        self
            #if os(macOS)
            .listStyle(.inset)
            #else
            .listStyle(.insetGrouped)
            .listSectionSpacing(Theme.spacingM)
            #endif
            .posScreen()
    }

    /// 리스트 행을 대시보드 카드와 같은 유리 표면으로.
    func posRow() -> some View {
        self
            .listRowBackground(PosRowSurface())
            .listRowSeparatorTint(Color.primary.opacity(0.06))
    }

    /// 폼 기반 화면(설정·편집 시트).
    func posForm() -> some View {
        self
            .formStyle(.grouped)
            .posScreen()
    }
}

/// 리스트 행 바닥면 — 대시보드 유리 카드와 같은 재질.
struct PosRowSurface: View {
    var body: some View {
        Rectangle().fill(.ultraThinMaterial)
    }
}

// MARK: 섹션

/// 카드 밖에 놓이는 섹션 제목. 대시보드 카드 헤더와 같은 서체를 쓴다.
struct PosSectionTitle: View {
    let text: String
    var trailing: String?

    init(_ text: String, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(text)
                .font(Theme.caption().bold())
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(Theme.caption2())
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
    }
}

/// ScrollView 기반 화면에서 쓰는 유리 카드 섹션.
/// 제목은 카드 위에, 내용은 카드 안에 — 대시보드와 같은 리듬.
struct GlassSection<Content: View>: View {
    let title: String?
    var footnote: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, footnote: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            if let title {
                PosSectionTitle(title)
                    .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCardStyle()

            if let footnote {
                Text(footnote)
                    .font(Theme.caption2())
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// 카드 안 행 사이 구분선 — 아주 옅게.
struct PosDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 1)
            .padding(.vertical, Theme.spacingS)
    }
}

/// 카드 안의 표준 행: 아이콘 + 제목 + (값) + (>).
struct PosRow<Trailing: View>: View {
    let title: String
    var systemImage: String?
    var subtitle: String?
    var showsChevron: Bool = false
    @ViewBuilder let trailing: Trailing

    init(
        _ title: String,
        systemImage: String? = nil,
        subtitle: String? = nil,
        showsChevron: Bool = false,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.showsChevron = showsChevron
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Theme.spacingS) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.body())
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.caption2())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: Theme.spacingS)

            trailing

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(Theme.caption())
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 6)
    }
}

/// 상태를 나타내는 작은 알약 — 켜짐/꺼짐, 건수 등.
struct PosPill: View {
    let text: String
    var tint: Color?

    init(_ text: String, tint: Color? = nil) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint ?? .secondary)
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((tint ?? Color.primary).opacity(tint == nil ? 0.08 : 0.12), in: Capsule())
    }
}

// MARK: 금액 가리기
//
// 남 앞에서 앱을 열 때 잔액이 그대로 보이는 게 싫어서 넣은 스위치.
// 대시보드의 눈 버튼과 설정이 같은 값을 본다.

enum AmountPrivacy {
    static let key = "hideAmounts"
    static let mask = "••••••"

    /// 뷰가 아닌 곳에서 읽을 때 (위젯 스냅샷 등).
    static var isHidden: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    /// 가려야 하면 마스크로, 아니면 원문 그대로.
    static func text(_ value: String, hidden: Bool) -> String {
        hidden ? mask : value
    }
}


// MARK: 키보드 내리기
//
// 숫자 키패드(.decimalPad · .numberPad)에는 리턴 키가 없어서 한 번 올라오면
// 내릴 방법이 없다. 처음엔 키보드 위에 "완료" 막대를 얹었는데, 화면이 하나 더
// 생기는 꼴이라 보기 싫었다. 지금은 **키보드 밖 아무 데나 탭하면** 내려간다.
//
// 구현이 SwiftUI가 아니라 UIKit인 이유:
// `.onTapGesture` 를 화면 전체에 걸면 그 아래 버튼·리스트 행의 탭을 먹어버린다.
// 창(UIWindow)에 인식기를 하나 달고 `cancelsTouchesInView = false` 로 두면
// 터치가 아래로 그대로 흘러가서 버튼도 정상 동작한다.
//
// 대신 **입력 칸 위의 탭은 무시해야 한다.** 안 그러면 텍스트 필드를 누르는
// 순간 올라오자마자 다시 내려간다. 그래서 delegate 에서 터치가 닿은 뷰의
// 조상을 훑어 UITextField/UITextView/UIControl 이 있으면 인식기를 안 받는다.
//
// `posScreen()` 에 들어 있으니 새 화면은 아무것도 안 해도 따라온다.
// 설치는 창당 한 번만 되도록 막아뒀으므로 여러 화면에 붙어도 괜찮다.

#if os(iOS)
enum KeyboardDismiss {
    /// 어떤 칸에 포커스가 있든 내린다. `@FocusState` 가 필요 없어서
    /// 공용 모디파이어에서 쓸 수 있다.
    static func now() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }
}

/// 창에 한 번만 달기 위한 표식용 서브클래스.
private final class KeyboardDismissTap: UITapGestureRecognizer {}

private final class KeyboardDismissCoordinator: NSObject, UIGestureRecognizerDelegate {

    static let shared = KeyboardDismissCoordinator()

    func install(on window: UIWindow) {
        let already = window.gestureRecognizers?.contains { $0 is KeyboardDismissTap } ?? false
        guard !already else { return }

        let tap = KeyboardDismissTap(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false   // 아래 뷰의 탭을 막지 않는다
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
    }

    @objc private func handleTap() {
        KeyboardDismiss.now()
    }

    /// 입력 칸·컨트롤 위의 탭은 받지 않는다.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        var node = touch.view
        while let current = node {
            if current is UITextField || current is UITextView || current is UIControl {
                return false
            }
            node = current.superview
        }
        return true
    }

    /// SwiftUI 자체 제스처와 같이 인식되게 둔다.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

/// 뷰 계층에 잠깐 끼어들어 자기 창을 찾아 인식기를 달아주는 껍데기.
private struct KeyboardDismissInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            if let window = view.window {
                KeyboardDismissCoordinator.shared.install(on: window)
            }
        }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        if let window = view.window {
            KeyboardDismissCoordinator.shared.install(on: window)
        }
    }
}
#endif

private struct PosKeyboardDismiss: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .scrollDismissesKeyboard(.interactively)
            .background(KeyboardDismissInstaller().frame(width: 0, height: 0))
        #else
        content
        #endif
    }
}

extension View {
    func posKeyboardDismissable() -> some View { modifier(PosKeyboardDismiss()) }
}
