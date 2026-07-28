import SwiftUI

enum Theme {
    // MARK: - Colors
    static let accent = Color("AccentColor")
    static let background = Color(.systemBackground)
    static let secondaryBackground = Color(.secondarySystemBackground)
    static let groupedBackground = Color(.systemGroupedBackground)

    static let expenseRed = Color(.systemRed)
    static let incomeGreen = Color(red: 0.2, green: 0.78, blue: 0.35)
    static let positiveGreen = Color(red: 0.2, green: 0.78, blue: 0.35)
    static let negativeRed = Color(.systemRed)
    static let neutralGray = Color(.secondaryLabel)

    static let priorityHigh = Color(.systemRed)
    static let priorityMedium = Color(.systemOrange)
    static let priorityLow = Color(.systemBlue)

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

// MARK: - Amount Formatting

extension Double {
    func formattedKRW() -> String {
        Currency.krw.format(self)
    }

    func formattedUSD() -> String {
        Currency.usd.format(self)
    }

    func formattedAmount(currency: String = "KRW") -> String {
        currency == "USD" ? formattedUSD() : formattedKRW()
    }
}
