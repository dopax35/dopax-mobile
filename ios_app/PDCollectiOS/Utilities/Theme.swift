import SwiftUI

extension Color {
    static let dopaxDarkBlue = Color(hex: 0x0F0F3D)
    static let dopaxBlue = Color(hex: 0x2828C6)
    static let dopaxOrange = Color(hex: 0xFF5C35)
    static let dopaxPurple = Color(hex: 0x5B34A4)
    static let dopaxWarmGray = Color(hex: 0xF0F4F8)
    
    // Legacy maps to ease transition
    static let primaryBlue = dopaxBlue
    static let secondaryPurple = dopaxPurple
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
            .font(.custom("Outfit-Medium", size: 12))
            .textCase(.uppercase)
    }
}

extension View {
    func dopaxH1() -> some View { modifier(DopaxH1()) }
    func dopaxH2() -> some View { modifier(DopaxH2()) }
    func dopaxH3() -> some View { modifier(DopaxH3()) }
    func dopaxH4() -> some View { modifier(DopaxH4()) }
}
