import SwiftUI

struct QuestionnaireView: View {
    @EnvironmentObject var appState: AppState
    @State private var symptoms  = 3
    @State private var motor     = 3
    @State private var sleep     = 3
    @State private var mood      = 3
    @State private var overall   = 3
    @State private var notes     = ""
    @State private var submitted = false

    var body: some View {
        NavigationStack {
            if submitted {
                thankYouView
            } else {
                Form {
                    Section {
                        Text(Date().formatted(date: .long, time: .omitted))
                            .foregroundColor(.secondary)
                    }

                    ratingSection("Motor Symptoms",
                        subtitle: "Tremor, stiffness, slowness today",
                        icon: "hand.raised", binding: $symptoms,
                        labels: ["None", "Mild", "Moderate", "Marked", "Severe"])

                    ratingSection("Motor Function",
                        subtitle: "How well can you move and perform daily tasks?",
                        icon: "figure.walk", binding: $motor,
                        labels: ["Very Poor", "Poor", "Fair", "Good", "Excellent"])

                    ratingSection("Sleep Quality",
                        subtitle: "How well did you sleep last night?",
                        icon: "moon.zzz", binding: $sleep,
                        labels: ["Very Poor", "Poor", "Fair", "Good", "Excellent"])

                    ratingSection("Mood",
                        subtitle: "How is your mood today?",
                        icon: "face.smiling", binding: $mood,
                        labels: ["Very Low", "Low", "Neutral", "Good", "Very Good"])

                    ratingSection("Overall Wellbeing",
                        subtitle: "Overall how are you feeling today?",
                        icon: "heart", binding: $overall,
                        labels: ["Very Poor", "Poor", "Fair", "Good", "Excellent"])

                    Section("Notes (optional)") {
                        TextEditor(text: $notes)
                            .frame(minHeight: 80)
                    }

                    Section {
                        Button("Submit") { submit() }
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                .navigationTitle("Daily Survey")
            }
        }
    }

    @ViewBuilder
    private func ratingSection(_ title: String, subtitle: String, icon: String, binding: Binding<Int>, labels: [String]) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: icon).foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).fontWeight(.medium)
                        Text(subtitle).font(.caption).foregroundColor(.secondary)
                    }
                }

                HStack {
                    ForEach(1...5, id: \.self) { val in
                        VStack(spacing: 4) {
                            Circle()
                                .fill(binding.wrappedValue >= val ? Color.blue : Color(.systemGray4))
                                .frame(width: 32, height: 32)
                                .overlay(Text("\(val)").font(.caption).fontWeight(.bold).foregroundColor(.white))
                                .onTapGesture { binding.wrappedValue = val }
                            Text(labels[val - 1])
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(width: 48)
                        }
                        if val < 5 { Spacer() }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var thankYouView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72)).foregroundColor(.green)
            Text("Survey Submitted").font(.title).fontWeight(.bold)
            Text("Thank you for completing today's survey.")
                .foregroundColor(.secondary).multilineTextAlignment(.center)
            Button("Done") { submitted = false; resetForm() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func submit() {
        let response = QuestionnaireResponse(
            timestamp: Date(),
            symptomsSeverity: symptoms,
            motorFunction: motor,
            sleepQuality: sleep,
            moodRating: mood,
            overallWellbeing: overall,
            notes: notes
        )
        appState.dataManager.writeQuestionnaire(response)
        submitted = true
    }

    private func resetForm() {
        symptoms = 3; motor = 3; sleep = 3; mood = 3; overall = 3; notes = ""
    }
}
