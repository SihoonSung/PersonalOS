import SwiftUI

/// 파스텔 그라디언트 + 소프트 블롭 배경 — 글래스 카드가 샘플링할 캔버스
struct DashboardBackground: View {
    @Environment(\.colorScheme) private var scheme

    private var gradientColors: [Color] {
        if scheme == .dark {
            return [
                Color(red: 0.055, green: 0.055, blue: 0.065),
                Color(red: 0.075, green: 0.075, blue: 0.09)
            ]
        }
        return [
            Color(red: 0.972, green: 0.965, blue: 0.955),
            Color(red: 0.945, green: 0.945, blue: 0.955)
        ]
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom)

            // 거의 느껴지지 않는 온기 — 유리가 샘플링할 미묘한 톤 변화만 남긴다
            Circle()
                .fill(Color.orange.opacity(scheme == .dark ? 0.05 : 0.06))
                .frame(width: 420, height: 420)
                .blur(radius: 130)
                .offset(x: 140, y: -320)

            Circle()
                .fill(Color.indigo.opacity(scheme == .dark ? 0.07 : 0.05))
                .frame(width: 460, height: 460)
                .blur(radius: 140)
                .offset(x: -160, y: 300)
        }
        .ignoresSafeArea()
    }
}
