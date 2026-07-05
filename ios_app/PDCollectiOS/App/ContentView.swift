import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.authManager.currentUser == nil {
                LoginView()
            } else if !appState.userProfile.consentGiven {
                ConsentView()
            } else if !appState.userProfile.profileComplete {
                ProfileSetupView()
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.userProfile.consentGiven)
        .animation(.easeInOut(duration: 0.3), value: appState.userProfile.profileComplete)
    }
}
