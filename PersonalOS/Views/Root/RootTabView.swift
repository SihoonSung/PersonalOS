import SwiftUI

struct RootTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label("홈", systemImage: "house.fill") }
                .tag(0)

            TasksView()
                .tabItem { Label("할 일", systemImage: "checkmark.circle.fill") }
                .tag(1)

            BudgetView()
                .tabItem { Label("가계부", systemImage: "wonsign.circle.fill") }
                .tag(2)

            // Month-1: 투자, AI 탭 추가 예정
            // InvestmentView()
            //     .tabItem { Label("투자", systemImage: "chart.line.uptrend.xyaxis") }
            //     .tag(3)
            //
            // AIAssistantView()
            //     .tabItem { Label("AI", systemImage: "sparkles") }
            //     .tag(4)
        }
        .tint(.blue)
    }
}
