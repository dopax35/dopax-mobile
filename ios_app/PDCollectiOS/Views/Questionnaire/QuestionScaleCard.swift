import SwiftUI

/// One question of the daily questionnaire (Figma 601:2): a white card, a
/// five-step scale, and a word at each end so the numbers mean something.
struct QuestionScaleCard: View {
    let question: String
    /// The word under 1 and the word under 5, e.g. "Low" / "Good".
    let lowLabel: String
    let highLabel: String
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question)
                .font(.dopax(15, .semibold))
                .foregroundColor(.dopaxBlack90)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { step in
                    segment(step)
                }
            }

            HStack {
                Text(lowLabel)
                Spacer()
                Text(highLabel)
            }
            .font(.dopax(11.5))
            .foregroundColor(.onboardingTextTertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func segment(_ step: Int) -> some View {
        let selected = value == step
        return Button {
            value = step
        } label: {
            Text("\(step)")
                .font(.dopax(15, selected ? .bold : .medium))
                .foregroundColor(selected ? .white : .dopaxGray50)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(selected ? Color.onboardingAccent : Color.questionScaleIdle)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(step) of 5")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}
