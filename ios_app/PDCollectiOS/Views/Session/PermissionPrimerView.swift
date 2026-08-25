import AVFoundation
import SwiftUI

/// The camera (Figma 607:2) and microphone (618:2) primers.
///
/// Shown immediately before the OS prompt rather than at launch, so the ask
/// arrives with a reason attached. 607:57 and 619:2 in the design are this
/// screen with the system alert over it — the alert is the OS's, so the only
/// thing to build for them is the `Info.plist` copy underneath.
///
/// "Not now" is a real answer: the test is skipped, the session continues, and
/// the primer comes back next time. Nothing here refuses to take no.
struct PermissionPrimerView: View {
    let capability: TestCapability
    /// Called with whether the participant ended up granting access.
    let onDecision: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isRequesting = false

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 0) {
                Spacer(minLength: 40)

                icon

                Text(copy.title)
                    .font(.dopax(26, .bold))
                    .foregroundColor(.dopaxBlack90)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .lineLimit(2)
                    .padding(.top, 34)
                    .padding(.horizontal, 24)

                Text(copy.body)
                    .font(.dopax(15))
                    .foregroundColor(.dopaxBlack70)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300)
                    .padding(.top, 12)

                neverDoCard
                    .padding(.top, 32)
                    .padding(.horizontal, 24)

                Spacer(minLength: 32)

                OnboardingPrimaryButton(title: "Continue", enabled: !isRequesting) {
                    request()
                }
                .padding(.horizontal, 24)

                OnboardingSecondaryLink(title: "Not now", color: .onboardingTextTertiary) {
                    onDecision(false)
                    dismiss()
                }
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private var icon: some View {
        Circle()
            .fill(Color.todaySurfaceBrandIdle)
            .frame(width: 96, height: 96)
            .overlay(
                Image(systemName: copy.symbol)
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(.onboardingAccent)
            )
    }

    private var neverDoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What we never do")
                .font(.dopax(14, .bold))
                .foregroundColor(.dopaxBlack90)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(copy.reassurances, id: \.self) { line in
                    Text(line)
                        .font(.dopax(13.5))
                        .foregroundColor(.dopaxBlack70)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Copy

    private struct Copy {
        let title: String
        let body: String
        let symbol: String
        let reassurances: [String]
    }

    private var copy: Copy {
        switch capability {
        case .camera:
            return Copy(
                title: "One quick permission",
                body: "During tests, the front camera measures the distance between your face and the screen.",
                symbol: "camera",
                reassurances: [
                    "No photos or videos are taken.",
                    "Nothing is stored or sent.",
                    "Only a distance number is measured.",
                ]
            )
        case .microphone:
            return Copy(
                title: "Your voice, only during tests",
                body: "The microphone records only while you run the voice test, and you will see the recording indicator whenever it is on.",
                symbol: "mic",
                reassurances: [
                    "Never listens in the background.",
                    "You start and stop every recording.",
                    "Recordings are used for research only.",
                ]
            )
        }
    }

    // MARK: - The ask

    private func request() {
        isRequesting = true
        PermissionPrimerView.requestAccess(to: capability) { granted in
            isRequesting = false
            onDecision(granted)
            dismiss()
        }
    }

    /// Whether the OS would show a prompt, i.e. whether the primer is worth
    /// showing at all. Already-granted goes straight to the test; already-denied
    /// does too, because a second primer cannot undo a Settings-level refusal
    /// and the test screen handles the missing hardware itself.
    static func needsPrimer(for capability: TestCapability?) -> Bool {
        guard let capability else { return false }
        return AVCaptureDevice.authorizationStatus(for: mediaType(for: capability)) == .notDetermined
    }

    static func requestAccess(to capability: TestCapability,
                              completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: mediaType(for: capability)) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    private static func mediaType(for capability: TestCapability) -> AVMediaType {
        switch capability {
        case .camera: return .video
        case .microphone: return .audio
        }
    }
}
