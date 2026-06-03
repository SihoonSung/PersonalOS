import SwiftUI

struct RootTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label(L.tabHome, systemImage: "house.fill") }
                .tag(0)

            TasksView()
                .tabItem { Label(L.tabTasks, systemImage: "checkmark.circle.fill") }
                .tag(1)

            BudgetView()
                .tabItem { Label(L.tabBudget, systemImage: "creditcard.fill") }
                .tag(2)

            SettingsView()
                .tabItem { Label(L.tabSettings, systemImage: "person.circle.fill") }
                .tag(3)
        }
        .tint(.blue)
    }
}
