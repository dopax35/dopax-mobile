import SwiftUI

/// The screen shown the moment a session's last test is finished
/// (Figma 550:30 morning, 550:89 noon, 483:2 evening).
///
/// One layout, three skies. The point of it is the helix: the participant
/// should leave knowing the day counted, not just that a form was submitted.
struct SessionCompleteView: View {
    let period: SessionPeriod
    let name: String
    let completedCount: Int
    let totalCount: Int
    let duration: TimeInterval
    @ObservedObject var baseline: BaselineTracker
    let helixGrew: Bool
    let onDismiss: () -> Void

    /// Another window that is open right now, so the footer can offer it
    /// instead of a button with nothing behind it.
    var nextActionablePeriod: SessionPeriod?
    var onStartNext: ((SessionPeriod) -> Void)?

    var body: some View {
        ZStack(alignment: .top) {
            Color.sessionCream.ignoresSafeArea()

            VStack(spacing: 0) {
                SessionSky(period: period)
                    .frame(height: 300)

                Spacer(minLength: 0)
            }
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                Spacer().frame(height: 314)

                textBlock

                Spacer(minLength: 24)

                footer
            }
        }
    }

    // MARK: - Text block

    private var textBlock: some View {
        VStack(spacing: 10) {
            Text(headline)
                .font(.dopax(28, .bold))
                .foregroundColor(.dopaxBlack90)

            Text("Your \(period.completionNoun) session is complete.")
                .font(.dopax(15))
                .foregroundColor(.dopaxBlack70)

            HStack(spacing: 10) {
                statChip(icon: "checkmark.circle",
                         text: "\(completedCount) of \(totalCount) tests")
                statChip(icon: "clock",
                         text: SessionManager.durationText(duration))
            }

            HelixProgress(day: baseline.currentDay,
                          total: BaselineTracker.totalDays,
                          caption: helixCaption)
                .padding(.top, 18)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }

    private var headline: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Beautiful work" : "Beautiful work, \(trimmed)"
    }

    /// Only the first completed session of a day moves the helix, so the
    /// second and third say where the day stands rather than claiming growth
    /// that did not happen.
    private var helixCaption: String {
        helixGrew
            ? baseline.progressCaption
            : "Day \(baseline.currentDay) of \(BaselineTracker.totalDays)"
    }

    private func statChip(icon: String, text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(period.completionAccent)
            Text(text)
                .font(.dopax(13.5, .bold))
                .foregroundColor(.dopaxBlack90)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white)
        .clipShape(Capsule())
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 10) {
            if let next = nextActionablePeriod {
                filledButton("Start \(next.completionNoun) session") {
                    onStartNext?(next)
                }
                ghostButton("Back to Today", action: onDismiss)
            } else {
                filledButton("Back to Today", action: onDismiss)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private func filledButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.dopax(16, .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(period.completionAccent)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func ghostButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.dopax(16, .bold))
                .foregroundColor(.dopaxBlack70)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sky

/// The illustrated panel, built from the exported Figma art rather than
/// redrawn: the mascot and wave are shared across all three, and each period
/// adds its own celestial body and star field.
private struct SessionSky: View {
    let period: SessionPeriod

    /// The design lays the sky out on a 390pt-wide frame; positions scale
    /// with the device so the moon does not drift off a narrower screen.
    private let designWidth: CGFloat = 390

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / designWidth

            ZStack(alignment: .topLeading) {
                gradient

                celestial(scale: scale)

                ForEach(Array(stars.enumerated()), id: \.offset) { _, star in
                    Image("SessionArtStar")
                        .resizable()
                        .frame(width: star.size * scale, height: star.size * scale)
                        .rotationEffect(.degrees(star.rotation))
                        .offset(x: star.x * scale, y: star.y * scale)
                }

                Image("OnboardingDopa")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 132 * scale, height: 132 * scale)
                    .offset(x: 129 * scale, y: 128 * scale)

                Image("SessionArtWave")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundColor(waveColor)
                    .frame(width: 96 * scale)
                    .opacity(0.8)
                    .offset(x: 196 * scale, y: 244 * scale)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
        }
    }

    @ViewBuilder
    private func celestial(scale: CGFloat) -> some View {
        switch period {
        case .morning:
            Image("SessionArtMorning")
                .resizable()
                .scaledToFit()
                .frame(width: 150 * scale)
                .offset(x: 236 * scale, y: 60 * scale)

        case .noon:
            Image("SessionArtNoon")
                .resizable()
                .scaledToFit()
                .frame(width: 150 * scale)
                .offset(x: 236 * scale, y: 28 * scale)

        case .night:
            ZStack(alignment: .topLeading) {
                Image("SessionArtGlow")
                    .resizable()
                    .frame(width: 150 * scale, height: 150 * scale)
                    .offset(x: 246 * scale, y: 28 * scale)
                Image("SessionArtMoon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 77.58 * scale)
                    .offset(x: 290 * scale, y: 48.52 * scale)
            }
        }
    }

    private struct Star {
        let x: CGFloat, y: CGFloat, size: CGFloat, rotation: Double
    }

    private var stars: [Star] {
        [
            Star(x: 42.13, y: 58, size: 19.4, rotation: 14),
            Star(x: 112, y: 117.92, size: 11.86, rotation: -12),
            Star(x: 196, y: 40.69, size: 14.84, rotation: -16),
            Star(x: 335.3, y: 170, size: 10.67, rotation: 4),
            Star(x: 70, y: 166.44, size: 10.43, rotation: -10),
        ]
    }

    /// The wave reads as a highlight, so it lightens the night sky and turns
    /// near-white against the two daytime ones.
    private var waveColor: Color {
        period == .night ? Color(hex: 0xC8BDFF) : Color.white.opacity(0.9)
    }

    private var gradient: LinearGradient {
        switch period {
        case .morning:
            return LinearGradient(colors: [.skyMorningTop, .skyMorningBottom],
                                  startPoint: .top, endPoint: .bottom)
        case .noon:
            return LinearGradient(colors: [.skyNoonTop, .skyNoonBottom],
                                  startPoint: .top, endPoint: .bottom)
        case .night:
            return LinearGradient(colors: [.skyEveningTop, .skyEveningBottom],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

// MARK: - Helix

/// Helix art over a 14-segment day scale — the same component the baseline
/// screen and the Profile card use, so the day count cannot disagree between
/// the three places it appears.
struct HelixProgress: View {
    let day: Int
    let total: Int
    let caption: String

    var body: some View {
        VStack(spacing: 10) {
            Image("SessionArtHelix")
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 56)

            HStack(spacing: 5) {
                ForEach(0..<total, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(index < day ? Color.onboardingAccentSoft : Color.todaySurfaceBrandStrong)
                        .frame(width: 13, height: 8)
                }
            }

            Text(caption)
                .font(.dopax(13.5, .medium))
                .foregroundColor(.todayTextOnChip)
        }
    }
}

// MARK: - Period presentation

extension SessionPeriod {
    /// The completion screen's call-to-action colour, sampled per sky so the
    /// button sits in the same family as the art above it.
    var completionAccent: Color {
        switch self {
        case .morning: return .dopaxOrange
        case .noon:    return .sessionNoonAccent
        case .night:   return .sessionNightAccent
        }
    }
}
