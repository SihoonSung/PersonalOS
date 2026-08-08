import SwiftUI

enum Theme {
    // MARK: - Colors (cross-platform: iOS/visionOS use UIKit, macOS uses AppKit)
    static let accent = Color("AccentColor")

    #if os(macOS)
    static let background = Color(nsColor: .windowBackgroundColor)
    static let secondaryBackground = Color(nsColor: .controlBackgroundColor)
    static let groupedBackground = Color(nsColor: .windowBackgroundColor)
    static let neutralGray = Color(nsColor: .secondaryLabelColor)
    static let expenseRed = Color(nsColor: .systemRed)
    static let negativeRed = Color(nsColor: .systemRed)
    static let priorityHigh = Color(nsColor: .systemRed)
    static let priorityMedium = Color(nsColor: .systemOrange)
    static let priorityLow = Color(nsColor: .systemBlue)
    #else
    static let background = Color(uiColor: .systemBackground)
    static let secondaryBackground = Color(uiColor: .secondarySystemBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let neutralGray = Color(uiColor: .secondaryLabel)
    static let expenseRed = Color(uiColor: .systemRed)
    static let negativeRed = Color(uiColor: .systemRed)
    static let priorityHigh = Color(uiColor: .systemRed)
    static let priorityMedium = Color(uiColor: .systemOrange)
    static let priorityLow = Color(uiColor: .systemBlue)
    #endif

    static let incomeGreen = Color(red: 0.2, green: 0.78, blue: 0.35)
    static let positiveGreen = Color(red: 0.2, green: 0.78, blue: 0.35)

    // MARK: - Typography
    static func largeTitle() -> Font { .largeTitle.bold() }
    static func title() -> Font { .title2.bold() }
    static func headline() -> Font { .headline }
    static func body() -> Font { .body }
    static func caption() -> Font { .caption }
    static func caption2() -> Font { .caption2 }

    // MARK: - Spacing
    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 16
    static let spacingL: CGFloat = 24
    static let spacingXL: CGFloat = 32

    // MARK: - Corner Radius
    static let radiusS: CGFloat = 8
    static let radiusM: CGFloat = 12
    static let radiusL: CGFloat = 16
    static let radiusXL: CGFloat = 20

    // MARK: - Card Style
    static func card() -> some ViewModifier { CardModifier() }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.spacingM)
            .background(Theme.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }

    /// Liquid Glass 카드 — 대시보드 전용
    func glassCardStyle(cornerRadius: CGFloat = Theme.radiusXL, interactive: Bool = false) -> some View {
        self
            .padding(Theme.spacingM)
            .glassEffect(
                interactive ? .regular.interactive() : .regular,
                in: .rect(cornerRadius: cornerRadius)
            )
    }
}

extension Theme {
    /// 글래스 대시보드 — 게이지/차트용 절제된 잉크 컬러 (모노크롬)
    static let glassInk = Color.primary
    static let glassTrack = Color.primary.opacity(0.08)
}
