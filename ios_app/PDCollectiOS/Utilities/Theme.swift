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

struct DopaxH1: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.custom("Rajdhani-Bold", size: 50))
            .lineSpacing(10)
    }
}

struct DopaxH2: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.custom("Rajdhani-Bold", size: 28))
    }
}

struct DopaxH3: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.custom("Rajdhani-Medium", size: 20))
            .textCase(.uppercase)
            .tracking(1.2)
    }
}

struct DopaxH4: ViewModifier {
    func body(content: Content) -> some View {
        content
            // The bundled Outfit.ttf's real PostScript name is "Outfit-Thin"
            // (confirmed via the font's name table) — there is no Medium
            // weight file in the project. Referencing "Outfit-Medium" here
            // never matched, so this label style silently rendered in the
            // system font instead of Outfit. If a Medium weight is wanted
            // for legibility at this small (12pt) size, add an
            // Outfit-Medium.ttf to the project and register it in Info.plist.
            .font(.custom("Outfit-Thin", size: 12))
            .textCase(.uppercase)
    }
}

extension View {
    func dopaxH1() -> some View { modifier(DopaxH1()) }
    func dopaxH2() -> some View { modifier(DopaxH2()) }
    func dopaxH3() -> some View { modifier(DopaxH3()) }
    func dopaxH4() -> some View { modifier(DopaxH4()) }
}
