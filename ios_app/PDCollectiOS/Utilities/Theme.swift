import SwiftUI

extension Color {
    static let dopaxDarkBlue = Color(hex: 0x0F0F3D)
    static let dopaxBlue = Color(hex: 0x2828C6)
    static let dopaxOrange = Color(hex: 0xFF5C35)
    static let dopaxPurple = Color(hex: 0x5B34A4)
    static let dopaxRose = Color(hex: 0xE63946)
    static let dopaxTeal = Color(hex: 0x00A896)
    static let dopaxWarmGray = Color(hex: 0xF0F4F8)

    // Onboarding (Figma Dopa-X user app)
    static let onboardingCream = Color(hex: 0xFFF5F1)
    static let onboardingAccent = Color(hex: 0x5B34A4)
    static let onboardingAccentSoft = Color(hex: 0x6E56C8)
    static let onboardingDotIdle = Color(hex: 0xE4DCE8)
    static let onboardingDotPast = Color(hex: 0xB9AFE8)
    static let onboardingTextTertiary = Color(hex: 0xA3A3A3)

    // Today / session flow (Figma "Current Design")
    static let todaySurfaceBrand = Color(hex: 0xF4F1F8)        // task + hub icon wells
    static let todaySurfaceBrandStrong = Color(hex: 0xE9E5F8)  // article thumbnails, window chip
    static let todaySurfaceBrandIdle = Color(hex: 0xEDE9FA)    // icon well on a not-yet-run hub row
    static let todayTextDisabled = Color(hex: 0xC4BBC8)        // locked session card text
    static let todayAccentWarm = Color(hex: 0xFF8953)          // morning/noon session button
    static let todayTextOnChip = Color(hex: 0x5A4A8A)          // window chip label
    static let sessionDemoStroke = Color(hex: 0x9B87E8)        // ready-gate demo line art
    static let questionScaleIdle = Color(hex: 0xF2F2F5)        // unselected scale segment

    /// The coral the two "commit this" buttons share — Save on the
    /// questionnaire (601:2) and Add medication on the sheet (475:2). Warmer
    /// and more urgent than `todayAccentWarm`, which only invites.
    static let sheetAccentCoral = Color(hex: 0xFF5C33)
    static let todayMorningTop = Color(hex: 0xFFD9AE)
    static let todayMorningBottom = Color(hex: 0xFFC08A)
    static let todayNoonTop = Color(hex: 0xFFD079)
    static let todayNoonBottom = Color(hex: 0xE7D0C6)
    static let todayNightTop = Color(hex: 0x2E2A4A)
    static let todayNightBottom = Color(hex: 0x4A4468)

    /// The success green the session screens use. Deliberately not
    /// `dopaxStatusSuccess`: that is the Material-derived hue the researcher
    /// surfaces share with Android, and the design uses a deeper green against
    /// the cream backgrounds so a check does not read as a system alert.
    static let sessionSuccess = Color(hex: 0x2E9E63)

    // Session complete (Figma 550:30 morning, 550:89 noon, 483:2 evening).
    // The page sits a shade warmer than `onboardingCream`, which is why it is
    // its own token rather than a reuse.
    static let sessionCream = Color(hex: 0xFFF7F2)
    static let skyMorningTop = Color(hex: 0xFFD7AB)
    static let skyMorningBottom = Color(hex: 0xFFC38F)
    static let skyNoonTop = Color(hex: 0xFFEFBB)
    static let skyNoonBottom = Color(hex: 0xFFE298)
    static let skyEveningTop = Color(hex: 0x4444E4)
    static let skyEveningBottom = Color(hex: 0x6A6ADB)

    /// Completion-screen call to action, one per sky.
    static let sessionNoonAccent = Color(hex: 0xFF9253)
    static let sessionNightAccent = Color(hex: 0x5252FF)

    // Baseline complete (Figma 579:2)
    static let baselineSkyTop = Color(hex: 0xE9E2F9)
    static let baselineSkyBottom = Color(hex: 0xFCF1E9)

    // Neutrals — mirror Android's colors.xml Dopa-X Brand Palette grays
    // (black_90/black_80/black_70/gray_50/gray_30), so both platforms draw
    // from the same named neutral scale instead of each picking its own
    // one-off grays. Added during the July 2026 color-consistency pass.
    static let dopaxBlack90 = Color(hex: 0x3D3D3D)
    static let dopaxBlack80 = Color(hex: 0x525252)
    static let dopaxBlack70 = Color(hex: 0x666666)
    static let dopaxGray50 = Color(hex: 0x8F8F8F)
    static let dopaxGray30 = Color(hex: 0xCCCCCC)

    // Semantic status colors — meaning (destructive/error, connected/success)
    // is universal and intentionally distinct from the brand hues above.
    // Mirrors Android's `error` / `status_success` / `status_error` resources.
    static let dopaxError = Color(hex: 0xB00020)
    static let dopaxStatusSuccess = Color(hex: 0x4CAF50)
    static let dopaxStatusError = Color(hex: 0xF44336)

    // Legacy maps to ease transition
    static let primaryBlue = dopaxBlue
    static let secondaryPurple = dopaxPurple
}

extension ShapeStyle where Self == Color {
    static var dopaxDarkBlue: Color { .dopaxDarkBlue }
    static var dopaxBlue: Color { .dopaxBlue }
    static var dopaxOrange: Color { .dopaxOrange }
    static var dopaxPurple: Color { .dopaxPurple }
    static var dopaxRose: Color { .dopaxRose }
    static var dopaxTeal: Color { .dopaxTeal }
    static var dopaxWarmGray: Color { .dopaxWarmGray }

    static var onboardingCream: Color { .onboardingCream }
    static var onboardingAccent: Color { .onboardingAccent }
    static var onboardingAccentSoft: Color { .onboardingAccentSoft }
    static var onboardingDotIdle: Color { .onboardingDotIdle }
    static var onboardingDotPast: Color { .onboardingDotPast }
    static var onboardingTextTertiary: Color { .onboardingTextTertiary }

    static var todaySurfaceBrand: Color { .todaySurfaceBrand }
    static var todaySurfaceBrandStrong: Color { .todaySurfaceBrandStrong }
    static var todaySurfaceBrandIdle: Color { .todaySurfaceBrandIdle }
    static var todayTextDisabled: Color { .todayTextDisabled }
    static var todayAccentWarm: Color { .todayAccentWarm }
    static var todayTextOnChip: Color { .todayTextOnChip }
    static var sessionSuccess: Color { .sessionSuccess }

    static var dopaxBlack90: Color { .dopaxBlack90 }
    static var dopaxBlack80: Color { .dopaxBlack80 }
    static var dopaxBlack70: Color { .dopaxBlack70 }
    static var dopaxGray50: Color { .dopaxGray50 }
    static var dopaxGray30: Color { .dopaxGray30 }

    static var dopaxError: Color { .dopaxError }
    static var dopaxStatusSuccess: Color { .dopaxStatusSuccess }
    static var dopaxStatusError: Color { .dopaxStatusError }

    static var primaryBlue: Color { .primaryBlue }
    static var secondaryPurple: Color { .secondaryPurple }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 08) & 0xff) / 255,
            blue: Double((hex >> 00) & 0xff) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Typography

/// Lexend is the product typeface on both platforms (Android sets it app-wide
/// in themes.xml). These are the four PostScript names bundled in Fonts/ and
/// registered under UIAppFonts — anything else silently falls back to SF Pro.
enum LexendFace {
    static let regular = "Lexend-Regular"
    static let medium = "Lexend-Medium"
    static let semibold = "Lexend-SemiBold"
    static let bold = "Lexend-Bold"

    static func name(for weight: Font.Weight) -> String {
        switch weight {
        case .medium: return medium
        case .semibold: return semibold
        case .bold, .heavy, .black: return bold
        default: return regular
        }
    }
}

extension Font {
    /// Drop-in replacement for `.system(size:weight:)`. Sizes stay fixed rather
    /// than using `relativeTo:` because the Figma layout pins button and field
    /// heights to 54/56pt — Dynamic Type scaling would overflow them.
    static func dopax(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(LexendFace.name(for: weight), size: size)
    }
}

struct DopaxH1: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.dopax(50, .bold))
            .lineSpacing(10)
    }
}

struct DopaxH2: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.dopax(28, .bold))
    }
}

struct DopaxH3: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.dopax(20, .medium))
            .textCase(.uppercase)
            .tracking(1.2)
    }
}

struct DopaxH4: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.dopax(12, .medium))
            .textCase(.uppercase)
    }
}

extension View {
    func dopaxH1() -> some View { modifier(DopaxH1()) }
    func dopaxH2() -> some View { modifier(DopaxH2()) }
    func dopaxH3() -> some View { modifier(DopaxH3()) }
    func dopaxH4() -> some View { modifier(DopaxH4()) }
}
