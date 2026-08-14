import SwiftUI

struct EmailSignInView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    let onSignedIn: () -> Void

    @State private var email = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var navigateToCode = false
    @State private var submittedEmail = ""
    @State private var resendCooldownSeconds = 60
    @FocusState private var emailFocused: Bool

    private var isValidEmail: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.contains("@") else { return false }
        guard let atIndex = trimmed.firstIndex(of: "@") else { return false }
        let afterAt = trimmed[trimmed.index(after: atIndex)...]
        return afterAt.contains(".")
    }

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(alignment: .leading, spacing: 0) {
                Text("Sign in with email")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.dopaxBlack90)
                    .padding(.top, 8)

                Text("We'll send a 6-digit code to confirm it's you.")
                    .font(.system(size: 14.5))
                    .foregroundColor(.dopaxBlack70)
                    .padding(.top, 8)

                TextField("alex@email.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .focused($emailFocused)
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(emailFocused ? Color.onboardingAccent : Color.clear, lineWidth: 1.5)
                    )
                    .padding(.top, 28)

                OnboardingPrimaryButton(
                    title: "Send code",
                    enabled: isValidEmail && !isSending
                ) {
                    sendCode()
                }
                .padding(.top, 20)

                Text("We only use your email to sign you in.")
                    .font(.system(size: 13))
                    .foregroundColor(.onboardingTextTertiary)
                    .padding(.top, 16)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundColor(.dopaxError)
                        .padding(.top, 12)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.dopaxBlack90)
                }
            }
        }
        .navigationDestination(isPresented: $navigateToCode) {
            EmailCodeView(
                email: submittedEmail,
                initialResendCooldownSeconds: resendCooldownSeconds,
                onSignedIn: onSignedIn
            )
        }
        .onAppear {
            emailFocused = true
        }
    }

    private func sendCode() {
        errorMessage = nil
        isSending = true
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)

        BackendSyncManager.shared.requestEmailCode(email: address) { result in
            isSending = false
            switch result {
            case .sent(_, _, let cooldown):
                submittedEmail = address
                resendCooldownSeconds = cooldown
                navigateToCode = true
            case .invalidRequest:
                errorMessage = "Please enter a valid email address."
            case .tooManyRequests(let retryAfter):
                errorMessage = "Too many attempts. Try again in \(retryAfter) seconds."
            case .emailDeliveryFailed:
                errorMessage = "We couldn't send the code. Please try again later."
            case .networkError:
                errorMessage = "Something went wrong. Please try again."
            }
        }
    }
}
