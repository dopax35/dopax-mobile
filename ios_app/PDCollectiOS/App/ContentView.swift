import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    /// The user is considered "past the login gate" if they are signed in to
    /// Firebase OR if they have explicitly chosen to continue without signing in.
    private var isAuthResolved: Bool {
        appState.authManager.currentUser != nil || appState.hasSkippedLogin
    }

    var body: some View {
        Group {
            if !isAuthResolved {
                LoginView()
            } else if !appState.userProfile.consentGiven {
                ConsentView()
            } else if !appState.userProfile.profileComplete {
                ProfileSetupView()
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isAuthResolved)
        .animation(.easeInOut(duration: 0.3), value: appState.userProfile.consentGiven)
        .animation(.easeInOut(duration: 0.3), value: appState.userProfile.profileComplete)
    }
}

