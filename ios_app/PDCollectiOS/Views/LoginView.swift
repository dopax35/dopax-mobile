import SwiftUI
import GoogleSignInSwift

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Spacer()

                Image(systemName: "waveform.path.ecg")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundColor(.dopaxBlue)

                Text("Welcome to PDCollect")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Sign in to back up your profile and sync across devices.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                Spacer()

                if isLoading {
                    ProgressView("Signing in…")
                        .padding()
                } else {
                    VStack(spacing: 16) {
                        Button(action: handleAppleSignIn) {
                            HStack {
                                Image(systemName: "apple.logo")
                                    .font(.title2)
                                Text("Sign in with Apple")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.black)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .padding(.horizontal)

                        Button(action: handleGoogleSignIn) {
                            HStack {
                                Image(systemName: "g.circle.fill")
                                    .font(.title2)
                                Text("Continue with Google")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.white)
                            .foregroundColor(.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .cornerRadius(8)
                        }
                        .padding(.horizontal)

                        // Escape hatch for users who already have a local profile
                        // (e.g. updated from a version that didn't require sign-in).
                        // Tapping this skips Firebase Auth entirely — local UserDefaults
                        // and Keychain data are fully preserved.
                        Button("Continue without signing in") {
                            // No-op: ContentView already shows the next screen
                            // based on consentGiven / profileComplete state.
                            // Marking the user as having acknowledged the login screen
                            // is handled implicitly by setting a flag so ContentView
                            // can route past LoginView without a Firebase user.
                            appState.skipSignIn()
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.dopaxError)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                Text("By signing in, you agree to our Privacy Policy and Terms of Service.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
        }
    }

    // MARK: - Sign-in Handlers

    private func handleGoogleSignIn() {
        isLoading = true
        errorMessage = nil
        appState.authManager.signInWithGoogle { result in
            handleSignInResult(result)
        }
    }

    private func handleAppleSignIn() {
        isLoading = true
        errorMessage = nil
        appState.authManager.signInWithApple { result in
            handleSignInResult(result)
        }
    }

    /// After Firebase auth succeeds, use syncProfileOnSignIn (local-wins merge)
    /// instead of loadProfileFromCloud (which would overwrite local data with
    /// whatever is in Firestore — potentially nothing for pre-auth users).
    private func handleSignInResult<T>(_ result: Result<T, Error>) {
        switch result {
        case .success:
            FirebaseSyncManager.shared.syncProfileOnSignIn(profile: appState.userProfile) { _ in
                DispatchQueue.main.async { isLoading = false }
            }
        case .failure(let error):
            isLoading = false
            // Don't show an error message when the user simply cancelled the sign-in sheet.
            if let authError = error as? AuthError, case .userCancelled = authError { return }
            errorMessage = error.localizedDescription
        }
    }
}
