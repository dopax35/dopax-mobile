import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showEmailSignIn = false
    @State private var emailCodeEnabled = BackendSyncManager.emailCodeEnabled

    /// Figma's Welcome screen offers Google, Apple and email only, so the
    /// "continue without signing in" escape hatch is hidden on fresh installs.
    /// It stays reachable on devices that already hold participant data:
    /// RELEASE.md added it precisely so an existing user who lands back on this
    /// screen is never walled off from data they already collected.
    private var showsLegacyAccessEscapeHatch: Bool {
        appState.userProfile.consentGiven || appState.hasSkippedLogin
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OnboardingBackground()

                VStack(spacing: 0) {
                    Spacer(minLength: 48)

                    OnboardingBrandMark()
                        .padding(.bottom, 26)

                    Text("Welcome to dopa-X")
                        .font(.dopax(30, .bold))
                        .foregroundColor(.dopaxBlack90)
                        .multilineTextAlignment(.center)

                    Text("A few minutes a day to track how your Parkinson’s really behaves.")
                        .font(.dopax(15))
                        .foregroundColor(.dopaxBlack70)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                        .padding(.horizontal, 36)

                    Text("Together, we’re working toward Levodopa timing that fits each person.")
                        .font(.dopax(13))
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

                        if emailCodeEnabled {
                            Button("Use email instead") {
                                showEmailSignIn = true
                            }
                            .font(.dopax(14, .medium))
                            .foregroundColor(.onboardingAccent)
                            .padding(.top, 20)
                        }

                        if showsLegacyAccessEscapeHatch {
                            OnboardingSecondaryLink(title: "Continue without signing in") {
                                appState.skipSignIn()
                            }
                            .padding(.top, emailCodeEnabled ? 8 : 20)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.dopaxError)
                            .font(.dopax(12))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }

                    Spacer(minLength: 24)

                    Text("For research participants of dopa-x.org")
                        .font(.dopax(12))
                        .foregroundColor(.onboardingTextTertiary)
                        .padding(.bottom, 28)
                }
            }
            .navigationDestination(isPresented: $showEmailSignIn) {
                EmailSignInView(onSignedIn: completePostAuthSignIn)
            }
        }
        .onAppear {
            BackendSyncManager.shared.fetchEmailCodeConfig { enabled in
                emailCodeEnabled = enabled
            }
        }
    }

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

    private func handleSignInResult<T>(_ result: Result<T, Error>) {
        switch result {
        case .success:
            completePostAuthSignIn()
        case .failure(let error):
            isLoading = false
            if let authError = error as? AuthError, case .userCancelled = authError { return }
            errorMessage = error.localizedDescription
        }
    }

    private func completePostAuthSignIn() {
        FirebaseSyncManager.shared.syncProfileOnSignIn(profile: appState.userProfile) { _ in
            BackendSyncManager.shared.ensureSession(preferredParticipantCode: appState.userProfile.userId) { _ in
                DispatchQueue.main.async { isLoading = false }
            }
        }
    }
}
