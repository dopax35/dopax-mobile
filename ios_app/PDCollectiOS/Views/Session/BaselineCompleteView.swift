import SwiftUI

/// The day-14 screen (Figma 579:2), shown exactly once.
///
/// It is the payoff the onboarding promised: for two weeks the app asked for
/// data and gave nothing back, and this is the moment that changes. The
/// one-shot guard lives in `BaselineTracker`, not here.
struct BaselineCompleteView: View {
    @ObservedObject var baseline: BaselineTracker
    let name: String
    let onContinue: () -> Void

    private let unlocks = [
        "Personal trends unlocked",
        "Your typical ranges unlocked",
        "Weekly summary unlocked",
    ]

    var body: some View {
        ZStack {
            LinearGradient(colors: [.baselineSkyTop, .baselineSkyBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                artwork
                    .padding(.top, 24)

                dayScale
                    .padding(.top, 26)

                headline
                    .padding(.top, 40)

                Spacer(minLength: 24)

                unlockList

                Spacer(minLength: 24)

                footer
            }
        }
    }

    // MARK: - Artwork

    private var artwork: some View {
        ZStack {
            Image("SessionArtHelixFull")
                .resizable()
                .scaledToFit()
                .frame(width: 300, height: 120)

            Image("OnboardingDopa")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .offset(y: -100)
        }
        .frame(height: 210)
        .overlay(alignment: .topLeading) {
            starField
        }
    }

    /// Scattered rather than evenly placed, matching the design's hand-set
    /// positions. Purely decorative, so it is excluded from accessibility.
    private var starField: some View {
        GeometryReader { geo in
            let scale = geo.size.width / 390
            ForEach(Array(stars.enumerated()), id: \.offset) { _, star in
                Image("SessionArtStar")
                    .resizable()
                    .frame(width: star.size * scale, height: star.size * scale)
                    .rotationEffect(.degrees(star.rotation))
                    .offset(x: star.x * scale, y: star.y * scale)
            }
        }
        .accessibilityHidden(true)
    }

    private struct Star {
        let x: CGFloat, y: CGFloat, size: CGFloat, rotation: Double
    }

    private var stars: [Star] {
        [
            Star(x: 33.16, y: 22, size: 25.6, rotation: 20),
            Star(x: 327.22, y: 2, size: 18.5, rotation: 10),
            Star(x: 190, y: -18, size: 13.9, rotation: -10),
            Star(x: 70, y: 190, size: 13.9, rotation: -10),
            Star(x: 318, y: 168, size: 17.6, rotation: -18),
        ]
    }

    private var dayScale: some View {
        HStack(spacing: 5) {
            ForEach(0..<BaselineTracker.totalDays, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.onboardingAccentSoft)
                    .frame(width: 13, height: 8)
            }
        }
    }

    // MARK: - Copy

    private var headline: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.dopax(27, .bold))
                .foregroundColor(.dopaxBlack90)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .lineLimit(2)

            Text(summary)
                .font(.dopax(15))
                .foregroundColor(.dopaxBlack70)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)
        }
        .padding(.horizontal, 24)
    }

    private var title: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Your baseline is ready" : "Your baseline is ready, \(trimmed)"
    }

    private var summary: String {
        let days = baseline.completedDays.count
        let sessions = baseline.completedSessions
        return "\(days) days, \(sessions) session\(sessions == 1 ? "" : "s"). "
            + "dopa-X now knows how you move — and can start showing you what it sees."
    }

    private var unlockList: some View {
        VStack(spacing: 8) {
            ForEach(unlocks, id: \.self) { unlock in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                    Text(unlock)
                        .font(.dopax(14, .medium))
                }
                .foregroundColor(.dopaxBlack90)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 16) {
            OnboardingPrimaryButton(title: "Show me my trends", action: onContinue)

            Text("Your helix keeps growing from here")
                .font(.dopax(13))
                .foregroundColor(.onboardingTextTertiary)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
}
