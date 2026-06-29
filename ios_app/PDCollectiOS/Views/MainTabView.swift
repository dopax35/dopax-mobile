import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis") }

            ActiveTestsView()
                .tabItem { Label("Tests", systemImage: "figure.walk") }

            DailyReportView()
                .tabItem { Label("Daily Report", systemImage: "list.clipboard") }

            DataExportView()
                .tabItem { Label("Data", systemImage: "square.and.arrow.up") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
