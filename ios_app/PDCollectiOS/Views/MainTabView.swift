import SwiftUI

struct MainTabView: View {
    /// Tags rather than positions, so reordering tabs in the shell rework
    /// cannot silently change which tab a jump lands on.
    private enum Tab: Hashable {
        case today, dashboard, tests, dailyReport, settings
    }

    @State private var selection: Tab = .today

    /// The period whose hub is open. Presented over the whole shell rather than
    /// pushed inside Today, because a session is a mode: the tab bar has no
    /// business being tappable while the battery is running.
    @State private var openSession: SessionPeriod?

    var body: some View {
        TabView(selection: $selection) {
            TodayView { period in openSession = period }
                .tabItem { Label("Today", systemImage: "house") }
                .tag(Tab.today)

            DashboardView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.dashboard)

            TestsTabView()
                .tabItem { Label("Tests", systemImage: "list.bullet") }
                .tag(Tab.tests)

            DailyReportView()
                .tabItem { Label("Daily Report", systemImage: "list.clipboard") }
                .tag(Tab.dailyReport)

            SettingsView()
                .tabItem { Label("Profile", systemImage: "person") }
                .tag(Tab.settings)
        }
        .fullScreenCover(item: $openSession) { period in
            SessionHubView(period: period)
        }
    }
}
