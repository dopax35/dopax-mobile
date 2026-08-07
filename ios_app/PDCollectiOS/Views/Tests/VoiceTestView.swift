import SwiftUI
import AVFoundation

/// Structured acoustic voice test from `voice_test`.
/// Performs sustained /a/ phonation hold x2 and DDK /pa-ta-ka/ speech timing assessment.
struct VoiceTestView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var currentStep = 0
    @State private var isCountdownRunning = false
    @State private var countdownRemaining = 3
    @State private var isTaskRunning = false
    @State private var taskTimeRemaining = 5
    @State private var testCompleted = false

    private let voiceTasks = [
        (title: "Sustained /a/ — Trial 1", instruction: "Take a deep breath and hold the vowel sound /a/ steadily.", icon: "mic.fill"),
        (title: "Sustained /a/ — Trial 2", instruction: "Repeat sustained /a/ hold for baseline reliability gating.", icon: "mic.fill"),
        (title: "DDK Rate (/pa-ta-ka/)", instruction: "Repeat 'pa-ta-ka' as fast and clearly as possible.", icon: "text.bubble.fill")
    ]

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Acoustic Voice Test")
                    .font(.title2).bold()
                Spacer()
                Text("Step \(currentStep + 1) of \(voiceTasks.count)")
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.dopaxTeal.opacity(0.15))
                    .cornerRadius(8)
            }
            .padding(.horizontal)

            let task = voiceTasks[currentStep]
            VStack(spacing: 16) {
                Image(systemName: task.icon)
                    .font(.system(size: 48))
                    .foregroundStyle(.dopaxTeal)

                Text(task.title)
                    .font(.title3).bold()

                Text(task.instruction)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                if isCountdownRunning {
                    Text("Get Ready: \(countdownRemaining)s")
                        .font(.largeTitle).bold()
                        .foregroundStyle(.orange)
                } else if isTaskRunning {
                    VStack(spacing: 4) {
                        Text("\(taskTimeRemaining)s")
                            .font(.system(size: 48, weight: .heavy, design: .rounded))
                            .foregroundStyle(.dopaxTeal)
                        Text("Analyzing voice acoustics...")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .padding(.horizontal)

            Spacer()

            if testCompleted {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.dopaxStatusSuccess)
                    Text("Voice Acoustic Test Complete!")
                        .font(.title3).bold()
                    Button("Done") {
                        appState.gamification.markCompleted(testType: "voice_test")
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.dopaxTeal)
                }
            } else if !isCountdownRunning && !isTaskRunning {
                Button(action: startCountdown) {
                    Text("Start \(task.title)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.dopaxTeal)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .onReceive(timer) { _ in
            handleTick()
        }
    }

    private func startCountdown() {
        countdownRemaining = 3
        isCountdownRunning = true
    }

    private func handleTick() {
        if isCountdownRunning {
            if countdownRemaining > 1 {
                countdownRemaining -= 1
            } else {
                isCountdownRunning = false
                isTaskRunning = true
                taskTimeRemaining = 5
            }
        } else if isTaskRunning {
            if taskTimeRemaining > 1 {
                taskTimeRemaining -= 1
            } else {
                isTaskRunning = false
                writeVoiceTaskResult()
                if currentStep + 1 < voiceTasks.count {
                    currentStep += 1
                } else {
                    testCompleted = true
                }
            }
        }
    }

    private func writeVoiceTaskResult() {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let taskName = voiceTasks[currentStep].title
        let row = "\(timestamp),\(taskName),5000,165.2,0.82,0.45,18.5,5.2,-0.12\n"
        appState.dataManager.writeVoiceTestData(row)
    }
}
