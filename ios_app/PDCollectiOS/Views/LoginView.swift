import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showEmailHint = false

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 0) {
                Spacer(minLength: 48)

                OnboardingBrandMark()
                    .padding(.bottom, 26)

                Text("Welcome to dopa-X")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.dopaxBlack90)
                    .multilineTextAlignment(.center)

                Text("A few minutes a day to track how your Parkinson’s really behaves.")
                    .font(.system(size: 15))
                    .foregroundColor(.dopaxBlack70)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .padding(.horizontal, 36)

                Text("Together, we’re working toward Levodopa timing that fits each person.")
                    .font(.system(size: 13))
                    .foregroundColor(.onboardingTextTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                    .padding(.horizontal, 48)

                Spacer()

                if isLoading {
                    ProgressView("Signing in…")
                        .padding(.bottom, 24)
                } else {
                    VStack(spacing: 12) {
                        OnboardingAuthCardButton(
                            title: "Continue with Google",
                            systemImage: nil,
                            assetImage: "GoogleLogo",
                            action: handleGoogleSignIn
                        )

                        OnboardingAuthCardButton(
                            title: "Continue with Apple",
                            systemImage: "apple.logo",
                            assetImage: nil,
                            action: handleAppleSignIn
                        )
                    }
                    .padding(.horizontal, 24)

                    // Same escape hatch as before — skips Firebase Auth;
                    // ContentView still gates on consentGiven / profileComplete.
                    OnboardingSecondaryLink(title: "Continue without signing in") {
                        appState.skipSignIn()
                    }
                    .padding(.top, 20)

                    Button("Use email instead") {
                        showEmailHint = true
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.onboardingAccent)
                    .padding(.top, 8)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.dopaxError)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                Spacer(minLength: 24)

                Text("For research participants of dopa-x.org")
                    .font(.system(size: 12))
                    .foregroundColor(.onboardingTextTertiary)
                    .padding(.bottom, 28)
            }
        }
        .alert("Email sign-in", isPresented: $showEmailHint) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please continue with Google or Apple. Email/password sign-in is not enabled in this build.")
        }
    }

    // MARK: - Sign-in Handlers (unchanged)

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
                BackendSyncManager.shared.ensureSession(preferredParticipantCode: appState.userProfile.userId) { _ in
                    DispatchQueue.main.async { isLoading = false }
                }
            }
        case .failure(let error):
            isLoading = false
            if let authError = error as? AuthError, case .userCancelled = authError { return }
            errorMessage = error.localizedDescription
        }
    }
}
