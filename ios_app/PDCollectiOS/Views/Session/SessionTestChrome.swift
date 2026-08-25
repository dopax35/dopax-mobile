import SwiftUI

/// The frame every test wears inside a session (Figma 576:2, 577:2, 577:41,
/// 577:69, 577:98, 577:128).
///
/// Those six frames are six different tests, but the border around them never
/// changes: position in the battery, a way out, the title, the instruction, and
/// whatever the test itself draws. Building it once means a test screen keeps
/// owning only its measurement, which is the part that must not be disturbed.
///
/// Everything but `title`, `instruction`, and the content is optional, because
/// the designs use each piece only where it earns its place — Trail Making has
/// a countdown and no hand chip, Spiral Tracing the reverse.
struct SessionTestChrome<Content: View>: View {
    /// 1-based. Nil outside a session, which hides the counter and Pause: a
    /// practice run from the Tests tab has no position and nothing to pause.
    var position: Int?
    var total: Int = SessionTest.dailyBattery.count
    let title: String
    let instruction: String
    /// The lavender pill, e.g. "Right hand · left is next".
    var sideChip: String?
    /// Whole seconds remaining. Nil for the self-paced tests.
    var secondsRemaining: Int?
    /// The grey line under the content, e.g. "Keep going — beautiful and steady".
    var hint: String?
    var onPause: (() -> Void)?
    let onEndEarly: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(alignment: .leading, spacing: 0) {
                header

                Text(title)
                    .font(.dopax(26, .bold))
                    .foregroundColor(.dopaxBlack90)
                    .padding(.top, 26)

                Text(instruction)
                    .font(.dopax(15))
                    .foregroundColor(.dopaxBlack70)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)

                if let sideChip {
                    Text(sideChip)
                        .font(.dopax(13, .medium))
                        .foregroundColor(.todayTextOnChip)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.todaySurfaceBrandStrong))
                        .padding(.top, 16)
                }

                if let secondsRemaining {
                    countdown(secondsRemaining)
                        .padding(.top, 20)
                }

                content()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 22)

                if let hint {
                    Text(hint)
                        .font(.dopax(13.5))
                        .foregroundColor(.onboardingTextTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                }

                Spacer(minLength: 24)

                Button("End test early", action: onEndEarly)
                    .font(.dopax(14.5, .medium))
                    .foregroundColor(.onboardingTextTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
        }
    }

    private var header: some View {
        HStack {
            if let position {
                Text("Test \(position) of \(total)")
                    .font(.dopax(13))
                    .foregroundColor(.dopaxBlack70)
            }

            Spacer()

            if let onPause {
                Button(action: onPause) {
                    HStack(spacing: 6) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("Pause")
                            .font(.dopax(13, .semibold))
                    }
                    .foregroundColor(.dopaxBlack90)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Capsule().fill(Color.white))
                }
            }
        }
        .frame(height: 32)
        .padding(.top, 8)
    }

    /// "32 s" — the number carries the weight, the unit stays out of the way.
    private func countdown(_ seconds: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(seconds)")
                .font(.dopax(40, .bold))
                .foregroundColor(.onboardingAccent)
                .monospacedDigit()
            Text("s")
                .font(.dopax(15, .medium))
                .foregroundColor(.onboardingTextTertiary)
        }
    }
}

/// What Pause opens. The design shows the pill but not the sheet behind it, so
/// this is deliberately the smallest thing that keeps the promise the hub's
/// footer makes: "Pause anytime — your progress is saved automatically."
struct SessionPauseSheet: View {
    let onResume: () -> Void
    let onLeave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.dopaxGray30)
                .frame(width: 40, height: 4)
                .padding(.top, 10)

            Text("Paused")
                .font(.dopax(22, .bold))
                .foregroundColor(.dopaxBlack90)
                .padding(.top, 26)

            Text("Take as long as you need. Finished tests are already saved — this one will restart when you come back.")
                .font(.dopax(15))
                .foregroundColor(.dopaxBlack70)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .padding(.horizontal, 24)

            OnboardingPrimaryButton(title: "Resume test", action: onResume)
                .padding(.top, 28)
                .padding(.horizontal, 24)

            OnboardingSecondaryLink(title: "Back to session",
                                    color: .onboardingTextTertiary,
                                    action: onLeave)
                .padding(.top, 18)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }
}
