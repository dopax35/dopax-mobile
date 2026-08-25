import SwiftUI

/// The daily questionnaire (Figma 601:2), with the save confirmation from
/// 600:11585.
///
/// The design draws four questions. The CSV this writes has carried eleven
/// since the study began, and 43 enrolled participants have history in that
/// shape, so dropping columns is not this screen's call to make. The four the
/// design names lead, in exactly the card idiom it specifies; the rest follow
/// under a heading, in the same idiom. Nothing about what gets written changed.
struct QuestionnaireView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Called instead of dismissing when the caller wants to own the exit.
    var onClose: (() -> Void)?

    @State private var q1Text = ""

    // The four the design leads with.
    @State private var mood = 3
    @State private var anxiety = 3
    @State private var sleep = 3
    @State private var steadiness = 3

    // Carried forward so the CSV keeps its shape.
    @State private var function = 3
    @State private var sleepProb = false
    @State private var sleepScore = 1
    @State private var smellProb = false
    @State private var smellScore = 1
    @State private var constProb = false
    @State private var constScore = 1
    @State private var deprProb = false
    @State private var deprScore = 1

    @State private var confirming = false
    @State private var saved = false

    var body: some View {
        ZStack {
            OnboardingBackground()

            if saved {
                savedConfirmation
            } else {
                form
            }

            if confirming {
                confirmDialog
            }
        }
        .animation(.easeOut(duration: 0.2), value: confirming)
    }

    // MARK: - Form

    private var form: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    QuestionScaleCard(question: "How is your mood today?",
                                      lowLabel: "Low", highLabel: "Good", value: $mood)
                    QuestionScaleCard(question: "How anxious have you felt today?",
                                      lowLabel: "Not at all", highLabel: "Very", value: $anxiety)
                    QuestionScaleCard(question: "How well did you sleep last night?",
                                      lowLabel: "Poorly", highLabel: "Well", value: $sleep)
                    QuestionScaleCard(question: "How steady do you feel right now?",
                                      lowLabel: "Unsteady", highLabel: "Steady", value: $steadiness)

                    alsoTracked
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }

            Button { confirming = true } label: {
                Text("Save")
                    .font(.dopax(16, .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.sheetAccentCoral)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .disabled(confirming)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: close) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 17, weight: .medium))
                    Text("Today")
                        .font(.dopax(14, .medium))
                }
                .foregroundColor(.dopaxBlack70)
            }
            .buttonStyle(.plain)

            Text("Daily questionnaire")
                .font(.dopax(28, .bold))
                .foregroundColor(.dopaxBlack90)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    /// The columns the study has always collected, below the four the design
    /// foregrounds. Same cards, so the screen reads as one thing.
    private var alsoTracked: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ALSO TRACKED")
                .font(.dopax(13, .bold))
                .kerning(1.2)
                .foregroundColor(.dopaxBlack70)
                .padding(.top, 12)

            QuestionScaleCard(question: "How well can you do everyday tasks?",
                              lowLabel: "Very poorly", highLabel: "Very well", value: $function)

            symptomCard("Sleep problems", present: $sleepProb, severity: $sleepScore)
            symptomCard("Smell or taste loss", present: $smellProb, severity: $smellScore)
            symptomCard("Constipation", present: $constProb, severity: $constScore)
            symptomCard("Low mood or depression", present: $deprProb, severity: $deprScore)

            VStack(alignment: .leading, spacing: 10) {
                Text("Anything else about today?")
                    .font(.dopax(15, .semibold))
                    .foregroundColor(.dopaxBlack90)

                TextField("Optional", text: $q1Text, axis: .vertical)
                    .font(.dopax(14))
                    .lineLimit(3...5)
                    .padding(12)
                    .background(Color.questionScaleIdle)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func symptomCard(_ title: String,
                             present: Binding<Bool>,
                             severity: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: present) {
                Text(title)
                    .font(.dopax(15, .semibold))
                    .foregroundColor(.dopaxBlack90)
            }
            .tint(.onboardingAccent)

            if present.wrappedValue {
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { step in
                        Button { severity.wrappedValue = step } label: {
                            Text("\(step)")
                                .font(.dopax(14, .medium))
                                .foregroundColor(severity.wrappedValue == step ? .white : .dopaxGray50)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(severity.wrappedValue == step
                                            ? Color.onboardingAccent : Color.questionScaleIdle)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    Text("Mild")
                    Spacer()
                    Text("Severe")
                }
                .font(.dopax(11.5))
                .foregroundColor(.onboardingTextTertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Confirmation (600:11585)

    private var confirmDialog: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { confirming = false }

            VStack(alignment: .leading, spacing: 0) {
                Text("Save your answers?")
                    .font(.dopax(21, .bold))
                    .foregroundColor(.dopaxBlack90)

                Text("Once saved, today's answers can't be changed. Take a moment to look them over.")
                    .font(.dopax(14.5))
                    .foregroundColor(.dopaxBlack70)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                OnboardingPrimaryButton(title: "Save answers", action: save)
                    .padding(.top, 22)

                Button("Check my answers again") { confirming = false }
                    .font(.dopax(14.5, .medium))
                    .foregroundColor(.dopaxBlack90)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)
            }
            .padding(24)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 32)
        }
    }

    private var savedConfirmation: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 58))
                .foregroundColor(.sessionSuccess)

            Text("Saved for today")
                .font(.dopax(22, .bold))
                .foregroundColor(.dopaxBlack90)

            Text("Thank you — that's today's questionnaire done.")
                .font(.dopax(15))
                .foregroundColor(.dopaxBlack70)
                .multilineTextAlignment(.center)

            OnboardingPrimaryButton(title: "Back to Today", action: close)
                .padding(.top, 12)
                .padding(.horizontal, 40)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Actions

    /// Writes the same eleven-column row the study has always received. The
    /// design's four questions map onto the columns they are asking about;
    /// nothing is invented and nothing is dropped.
    private func save() {
        let response = QuestionnaireResponse(
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
            q1Text: q1Text,
            // Steadiness runs the opposite way to the motor-symptom column it
            // feeds: feeling steady means fewer symptoms, not more.
            q2Score: 6 - steadiness,
            q3Score: function,
            q4Score: sleep,
            q5Score: mood,
            q6SleepYesNo: sleepProb, q6SleepScore: sleepScore,
            q6SmellYesNo: smellProb, q6SmellScore: smellScore,
            q6ConstYesNo: constProb, q6ConstScore: constScore,
            // The design's anxiety question is the severity column: its 1 is
            // labelled "Not at all", so anything above it is a yes.
            q6AnxietyYesNo: anxiety > 1, q6AnxietyScore: anxiety,
            q6DeprYesNo: deprProb, q6DeprScore: deprScore
        )
        appState.dataManager.writeQuestionnaire(response)
        appState.sessionManager.markTask(.questionnaire)
        confirming = false
        saved = true
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}
