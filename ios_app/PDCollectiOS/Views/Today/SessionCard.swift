import SwiftUI

/// A "TODAY'S SESSIONS" card.
///
/// One component, four states. The card expands to show its call to action
/// only when the participant can act on it; otherwise it collapses to a
/// two-line summary with a trailing status glyph, which is what keeps exactly
/// one card open in the design.
struct SessionCard: View {
    let period: SessionPeriod
    let state: SessionState
    let subtitle: String
    let action: () -> Void

    /// Width of the artwork panel, per the design.
    private let artWidth: CGFloat = 110

    private var isLocked: Bool { state == .locked }

    var body: some View {
        HStack(spacing: 0) {
            SessionCardArt(period: period, dimmed: isLocked)
                .frame(width: artWidth)

            controls
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(period.cardTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(isLocked ? .todayTextDisabled : .dopaxBlack90)

                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(isLocked ? .todayTextDisabled : .dopaxBlack70)
                        .lineSpacing(1.3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let title = callToAction {
                    Button(action: action) {
                        Text(title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(period.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let glyph = statusGlyph {
                Image(systemName: glyph.name)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(glyph.color)
                    .frame(width: 24, height: 24)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .opacity(isLocked ? 0.6 : 1)
    }

    /// Only an actionable session offers a button; the design collapses the
    /// rest to a glyph.
    private var callToAction: String? {
        switch state {
        case .available:  return "Start Session"
        case .inProgress: return "Resume"
        case .locked, .completed, .missed: return nil
        }
    }

    private var statusGlyph: (name: String, color: Color)? {
        switch state {
        case .completed: return ("checkmark", .dopaxStatusSuccess)
        case .locked:    return ("lock.fill", .todayTextDisabled)
        case .missed:    return ("moon.zzz.fill", .dopaxGray50)
        case .available, .inProgress: return nil
        }
    }
}

// MARK: - Artwork

/// The illustrated panel on the leading edge. Assets are the exported Figma
/// vectors; positions are the design's, and the panel clips so a collapsed
/// card shows the same crop the design does.
private struct SessionCardArt: View {
    let period: SessionPeriod
    let dimmed: Bool

    /// The artwork is an overlay rather than a stacked child so it cannot
    /// stretch the card: height comes from the controls, exactly as the design
    /// has it, and anything taller is clipped.
    var body: some View {
        gradient
            .frame(maxHeight: .infinity)
            .overlay(alignment: .topLeading) { artwork }
            .clipped()
    }

    @ViewBuilder
    private var artwork: some View {
        switch period {
        case .morning:
            Image("SessionArtMorning")
                .resizable()
                .frame(width: 80, height: 99.24)
                .offset(x: 15, y: 16.38)

        case .noon:
            Image("SessionArtNoon")
                .resizable()
                .frame(width: 80, height: 80)
                .offset(x: 15, y: 15)

        case .night:
            nightSky
        }
    }

    private var nightSky: some View {
        ZStack(alignment: .topLeading) {
            star(size: 4, x: 20, y: 25)
            star(size: 3, x: 80, y: 40)
            star(size: 4, x: 35, y: 80)
            star(size: 2, x: 75, y: 110)
            star(size: 12, x: 65, y: 20)

            Image("SessionArtMoon")
                .resizable()
                .frame(width: 43.05, height: 44)
                .offset(x: 33, y: 38)
        }
    }

    private func star(size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Image("SessionArtStar")
            .resizable()
            .frame(width: size, height: size)
            .offset(x: x, y: y)
    }

    /// A locked card is greyed regardless of period — the design shows this on
    /// the Night card, and it reads as "not yet" rather than "night".
    private var gradient: LinearGradient {
        if dimmed {
            return LinearGradient(
                colors: [Color(hex: 0xC6C6C6, alpha: 0.25), Color(hex: 0x636363, alpha: 0.25)],
                startPoint: .top, endPoint: .bottom)
        }
        switch period {
        case .morning:
            return LinearGradient(colors: [.todayMorningTop, .todayMorningBottom],
                                  startPoint: .top, endPoint: .bottom)
        case .noon:
            return LinearGradient(colors: [.todayNoonTop, .todayNoonBottom],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        case .night:
            return LinearGradient(colors: [.todayNightTop, .todayNightBottom],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

// MARK: - Period presentation

extension SessionPeriod {
    /// Session button colour. Matches the CTA on each completion screen: warm
    /// for the daytime sessions, brand purple after dark.
    var accent: Color {
        switch self {
        case .morning, .noon: return .todayAccentWarm
        case .night:          return .onboardingAccentSoft
        }
    }
}
