import SwiftUI

struct QuestionnaireView: View {
    @EnvironmentObject var appState: AppState

    // Q1 — free text
    @State private var q1Text = ""

    // Q2–Q5 — scored 1–5
    @State private var q2Motor     = 3   // motor symptoms
    @State private var q3Function  = 3   // motor function
    @State private var q4Sleep     = 3   // sleep quality
    @State private var q5Mood      = 3   // mood

    // Q6 — binary + severity
    @State private var sleepProb   = false; @State private var sleepScore   = 1
    @State private var smellProb   = false; @State private var smellScore   = 1
    @State private var constProb   = false; @State private var constScore   = 1
    @State private var anxietyProb = false; @State private var anxietyScore = 1
    @State private var deprProb    = false; @State private var deprScore    = 1

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

                    Section("How are you feeling today?") {
                        TextField("Describe your overall feeling…", text: $q1Text, axis: .vertical)
                            .lineLimit(3...5)
                    }

                    ratingSection("Motor Symptoms",
                        subtitle: "Tremor, stiffness, slowness today",
                        icon: "hand.raised", binding: $q2Motor,
                        labels: ["None", "Mild", "Moderate", "Marked", "Severe"])

                    ratingSection("Motor Function",
                        subtitle: "How well can you perform daily tasks?",
                        icon: "figure.walk", binding: $q3Function,
                        labels: ["Very Poor", "Poor", "Fair", "Good", "Excellent"])

                    ratingSection("Sleep Quality",
                        subtitle: "How well did you sleep last night?",
                        icon: "moon.zzz", binding: $q4Sleep,
                        labels: ["Very Poor", "Poor", "Fair", "Good", "Excellent"])

                    ratingSection("Mood",
                        subtitle: "How is your mood today?",
                        icon: "face.smiling", binding: $q5Mood,
                        labels: ["Very Low", "Low", "Neutral", "Good", "Very Good"])

                    Section {
                        Text("Please indicate any non-motor symptoms you've experienced.")
                            .font(.footnote).foregroundColor(.secondary)
                    }

                    nonMotorRow("Sleep Problems", toggle: $sleepProb, score: $sleepScore)
                    nonMotorRow("Smell / Taste Loss", toggle: $smellProb, score: $smellScore)
                    nonMotorRow("Constipation", toggle: $constProb, score: $constScore)
                    nonMotorRow("Anxiety", toggle: $anxietyProb, score: $anxietyScore)
                    nonMotorRow("Depression", toggle: $deprProb, score: $deprScore)

                    Section {
                        Button("Submit") { submit() }
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                            .padding(.vertical, 8)
                            .background(Color.dopaxBlue)
                            .cornerRadius(8)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                .navigationTitle("Daily Survey")
            }
        }
    }

    // MARK: - Rating Row

    @ViewBuilder
    private func ratingSection(_ title: String, subtitle: String, icon: String, binding: Binding<Int>, labels: [String]) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: icon).foregroundColor(.dopaxBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).fontWeight(.medium)
                        Text(subtitle).font(.caption).foregroundColor(.secondary)
                    }
                }
                HStack {
                    ForEach(1...5, id: \.self) { val in
                        VStack(spacing: 4) {
                            Circle()
                                .fill(binding.wrappedValue >= val ? Color.dopaxBlue : Color(.systemGray4))
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

    // MARK: - Non-motor Symptom Row

    @ViewBuilder
    private func nonMotorRow(_ title: String, toggle: Binding<Bool>, score: Binding<Int>) -> some View {
        Section {
            Toggle(title, isOn: toggle)
            if toggle.wrappedValue {
                Picker("Severity", selection: score) {
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: - Thank You

    private var thankYouView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72)).foregroundColor(.dopaxStatusSuccess)
            Text("Survey Submitted").font(.title).fontWeight(.bold)
            Text("Thank you for completing today's survey.")
                .foregroundColor(.secondary).multilineTextAlignment(.center)
            Button("Done") { submitted = false; resetForm() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Actions

    private func submit() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let response = QuestionnaireResponse(
            timestampMs: nowMs,
            q1Text: q1Text,
            q2Score: q2Motor,
            q3Score: q3Function,
            q4Score: q4Sleep,
            q5Score: q5Mood,
            q6SleepYesNo: sleepProb,   q6SleepScore: sleepScore,
            q6SmellYesNo: smellProb,   q6SmellScore: smellScore,
            q6ConstYesNo: constProb,   q6ConstScore: constScore,
            q6AnxietyYesNo: anxietyProb, q6AnxietyScore: anxietyScore,
            q6DeprYesNo: deprProb,     q6DeprScore: deprScore
        )
        appState.dataManager.writeQuestionnaire(response)
        submitted = true
    }

    private func resetForm() {
        q1Text = ""
        q2Motor = 3; q3Function = 3; q4Sleep = 3; q5Mood = 3
        sleepProb = false; sleepScore = 1
        smellProb = false; smellScore = 1
        constProb = false; constScore = 1
        anxietyProb = false; anxietyScore = 1
        deprProb = false; deprScore = 1
    }
}
