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
                
                Text("Sign in to sync your profile and contribute to Parkinson's research.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                Spacer()
                
                if isLoading {
                    ProgressView("Signing in...")
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
                    }
                }
                
                if let errorMessage = errorMessage {
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
            // Sync profile
            FirebaseSyncManager.shared.loadProfileFromCloud(profile: appState.userProfile) { success in
                isLoading = false
                if success {
                    print("Profile loaded from cloud.")
                } else {
                    print("New user or failed to load profile.")
                }
            }
        case .failure(let error):
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }
}
