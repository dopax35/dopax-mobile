import SwiftUI

struct EmailCodeView: View {
    @EnvironmentObject private var appState: AppState

    let email: String
    let initialResendCooldownSeconds: Int
    let onSignedIn: () -> Void

    @State private var code = ""
    @State private var isVerifying = false
    @State private var isResending = false
    @State private var errorMessage: String?
    @State private var secondsUntilResend: Int
    @FocusState private var codeFocused: Bool

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(email: String, initialResendCooldownSeconds: Int, onSignedIn: @escaping () -> Void) {
        self.email = email
        self.initialResendCooldownSeconds = initialResendCooldownSeconds
        self.onSignedIn = onSignedIn
        _secondsUntilResend = State(initialValue: initialResendCooldownSeconds)
    }

    private var canResend: Bool {
        secondsUntilResend <= 0 && !isResending
    }

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(alignment: .leading, spacing: 0) {
                Text("Enter the code")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.dopaxBlack90)
                    .padding(.top, 8)

                Text("Sent to \(email)")
                    .font(.system(size: 14.5))
                    .foregroundColor(.dopaxBlack70)
                    .padding(.top, 8)

                codeEntryRow
                    .padding(.top, 28)

                OnboardingPrimaryButton(
                    title: "Verify",
                    enabled: code.count == 6 && !isVerifying
                ) {
                    verifyCode()
                }
                .padding(.top, 24)

                Button {
                    resendCode()
                } label: {
                    Text("Resend")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .foregroundColor(canResend ? .onboardingAccent : .dopaxGray50)
                        .background(Color.onboardingDotIdle)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(!canResend)
                .padding(.top, 12)

                Text(resendCountdownText)
                    .font(.system(size: 13))
                    .foregroundColor(.onboardingTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)

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
        .onReceive(timer) { _ in
            if secondsUntilResend > 0 {
                secondsUntilResend -= 1
            }
        }
        .onAppear {
            codeFocused = true
        }
        .onChange(of: code) { newValue in
            let digits = newValue.filter(\.isNumber)
            code = String(digits.prefix(6))
            if code.count == 6 && !isVerifying {
                verifyCode()
            }
        }
    }

    private var resendCountdownText: String {
        if secondsUntilResend <= 0 {
            return "Resend code"
        }
        let minutes = secondsUntilResend / 60
        let seconds = secondsUntilResend % 60
        return String(format: "Resend code (in %d:%02d)", minutes, seconds)
    }

    private var codeEntryRow: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($codeFocused)
                .opacity(0.01)
                .frame(width: 1, height: 1)

            HStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { index in
                    digitBox(at: index)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { codeFocused = true }
        }
    }

    private func digitBox(at index: Int) -> some View {
        let digit = index < code.count
            ? String(code[code.index(code.startIndex, offsetBy: index)])
            : ""
        let isNextEmpty = index == code.count && code.count < 6

        return Text(digit)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.dopaxBlack90)
            .frame(width: 52, height: 56)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isNextEmpty ? Color.onboardingAccent : Color.clear, lineWidth: 1.5)
            )
    }

    private func verifyCode() {
        guard code.count == 6, !isVerifying else { return }
        errorMessage = nil
        isVerifying = true

        BackendSyncManager.shared.verifyEmailCode(email: email, code: code) { result in
            switch result {
            case .success(let customToken, _):
                appState.authManager.signInWithCustomToken(customToken) { authResult in
                    isVerifying = false
                    switch authResult {
                    case .success:
                        onSignedIn()
                    case .failure(let error):
                        errorMessage = error.localizedDescription
                    }
                }
            case .invalidCode(let reason, let attemptsRemaining):
                isVerifying = false
                errorMessage = invalidCodeMessage(reason: reason, attemptsRemaining: attemptsRemaining)
            case .signInUnavailable:
                isVerifying = false
                errorMessage = "Sign-in is temporarily unavailable."
            case .networkError:
                isVerifying = false
                errorMessage = "Something went wrong. Please try again."
            }
        }
    }

    private func resendCode() {
        guard canResend else { return }
        errorMessage = nil
        isResending = true

        BackendSyncManager.shared.requestEmailCode(email: email) { result in
            isResending = false
            switch result {
            case .sent(_, _, let cooldown):
                code = ""
                secondsUntilResend = cooldown
                codeFocused = true
            case .tooManyRequests(let retryAfter):
                secondsUntilResend = retryAfter
                errorMessage = "Too many attempts. Try again in \(retryAfter) seconds."
            case .emailDeliveryFailed:
                errorMessage = "We couldn't send the code. Please try again later."
            case .invalidRequest, .networkError:
                errorMessage = "Something went wrong. Please try again."
            }
        }
    }

    private func invalidCodeMessage(reason: EmailCodeVerifyInvalidReason, attemptsRemaining: Int?) -> String {
        switch reason {
        case .noActiveCode:
            return "No active code. Request a new one."
        case .expired:
            return "That code expired. Request a new one."
        case .tooManyAttempts:
            return "Too many wrong attempts. Request a new code."
        case .mismatch:
            if let remaining = attemptsRemaining {
                return "That code isn't right. \(remaining) attempts left."
            }
            return "That code isn't right."
        }
    }
}
