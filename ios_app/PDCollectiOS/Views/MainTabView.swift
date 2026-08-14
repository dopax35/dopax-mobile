import SwiftUI

struct MainTabView: View {
    /// Tags rather than positions, so reordering tabs in the Phase 2 shell
    /// rework cannot silently change which tab a jump lands on.
    private enum Tab: Hashable {
        case today, dashboard, tests, dailyReport, settings
    }

    @State private var selection: Tab = .today

    var body: some View {
        TabView(selection: $selection) {
            TodayView { _ in selection = .tests }
                .tabItem { Label("Today", systemImage: "house") }
                .tag(Tab.today)

            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.dashboard)

            ActiveTestsView()
                .tabItem { Label("Tests", systemImage: "figure.walk") }
                .tag(Tab.tests)

            DailyReportView()
                .tabItem { Label("Daily Report", systemImage: "list.clipboard") }
                .tag(Tab.dailyReport)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
    }
}
