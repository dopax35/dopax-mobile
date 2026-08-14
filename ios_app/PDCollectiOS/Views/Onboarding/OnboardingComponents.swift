import SwiftUI

/// Shared visual pieces for the Figma onboarding redesign.
/// Logic stays in LoginView / ConsentView / ProfileSetupView — these are presentation only.

struct OnboardingBackground: View {
    var body: some View {
        LinearGradient(
            colors: [.white, .onboardingCream],
            startPoint: .top,
            endPoint: UnitPoint(x: 0.5, y: 0.12)
        )
        .ignoresSafeArea()
    }
}

struct OnboardingProgressDots: View {
    let total: Int
    let current: Int // 0-based

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4)
                    .fill(fill(for: index))
                    .frame(width: index == current ? 22 : 7, height: 7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fill(for index: Int) -> Color {
        if index == current { return .onboardingAccentSoft }
        if index < current { return .onboardingDotPast }
        return .onboardingDotIdle
    }
}

struct OnboardingPrimaryButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .foregroundColor(.white)
                .background(enabled ? Color.onboardingAccent : Color.dopaxGray50)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .disabled(!enabled)
    }
}

struct OnboardingSecondaryLink: View {
    let title: String
    var color: Color = .onboardingAccent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundColor(color)
        }
    }
}

struct OnboardingFieldLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.dopaxBlack70)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OnboardingTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var isFocused: Bool = false

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboard)
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isFocused ? Color.onboardingAccent : Color.clear, lineWidth: 1.5)
            )
    }
}

struct OnboardingSegmentRow: View {
    let options: [String]
    @Binding var selection: String
    var fontSize: CGFloat = 15

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let selected = selection == option
                Button {
                    selection = option
                } label: {
                    Text(option)
                        .font(.system(size: fontSize, weight: .bold))
                        .foregroundColor(selected ? .white : .dopaxBlack70)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(selected ? Color.onboardingAccent : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct OnboardingAuthCardButton: View {
    let title: String
    let systemImage: String?
    let assetImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let assetImage {
                    Image(assetImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 22, height: 22)
                }
                Text(title)
                    .font(.system(size: 15.5, weight: .bold))
                    .foregroundColor(.dopaxBlack90)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }
}

struct OnboardingBrandMark: View {
    var faceSize: CGFloat = 120
    var helixWidth: CGFloat = 120

    var body: some View {
        VStack(spacing: 16) {
            Image("OnboardingDopa")
                .resizable()
                .scaledToFit()
                .frame(width: faceSize, height: faceSize)
            Image("OnboardingHelix")
                .resizable()
                .scaledToFit()
                .frame(width: helixWidth, height: helixWidth * 44 / 120)
        }
    }
}

struct OnboardingPrimerCard: View {
    let title: String
    let bodyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.dopaxBlack90)
            Text(bodyText)
                .font(.system(size: 14))
                .foregroundColor(.dopaxBlack70)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
