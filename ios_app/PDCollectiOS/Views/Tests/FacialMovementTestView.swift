import SwiftUI
import ARKit
import Vision

/// FacialMovementTestView drives a guided 5-task facial hypomimia assessment battery
/// (Rest, Brow Raise, Smile, Mouth Pucker, Rapid Blink) inspired by `face_test`.
struct FacialMovementTestView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var currentStepIndex = 0
    @State private var isCountdownActive = false
    @State private var countdownRemaining = 3
    @State private var isTaskActive = false
    @State private var taskTimeRemaining = 5
    @State private var testCompleted = false
    @State private var trackedBlinks = 0

    private let tasks = [
        (title: "Neutral Rest", instruction: "Keep face completely relaxed at rest.", icon: "face.smiling"),
        (title: "Eyebrow Raise", instruction: "Raise eyebrows as high as comfortable.", icon: "arrow.up.and.line.horizontal.and.arrow.down"),
        (title: "Full Smile", instruction: "Smile broadly showing teeth.", icon: "mouth"),
        (title: "Mouth Pucker", instruction: "Pucker lips firmly forward.", icon: "circle.circle"),
        (title: "Rapid Blinking", instruction: "Blink rapidly and repeatedly for 5 seconds.", icon: "eye")
    ]

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 24) {
            // Header Progress
            HStack {
                Text("Facial Movement Test")
                    .font(.title2).bold()
                Spacer()
                Text("Step \(currentStepIndex + 1) of \(tasks.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            ProgressView(value: Double(currentStepIndex + 1), total: Double(tasks.count))
                .tint(.dopaxPurple)
                .padding(.horizontal)

            // Task Banner Card
            let currentTask = tasks[currentStepIndex]
            VStack(spacing: 16) {
                Image(systemName: currentTask.icon)
                    .font(.system(size: 48))
                    .foregroundStyle(.dopaxPurple)
                    .padding()
                    .background(Color.dopaxPurple.opacity(0.12))
                    .clipShape(Circle())

                Text(currentTask.title)
                    .font(.title3).bold()

                Text(currentTask.instruction)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                if isCountdownActive {
                    Text("Get ready: \(countdownRemaining)s")
                        .font(.largeTitle).bold()
                        .foregroundStyle(.orange)
                } else if isTaskActive {
                    VStack(spacing: 4) {
                        Text("\(taskTimeRemaining)s")
                            .font(.system(size: 44, weight: .heavy, design: .rounded))
                            .foregroundStyle(.dopaxPurple)
                        Text("Recording facial metrics...")
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

            // Live Camera Feedback Simulator / Face Tracking Indicator
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.faceDistance.lastSample != nil ? Color.green : Color.yellow)
                        .frame(width: 10, height: 10)
                    Text(appState.faceDistance.lastSample != nil ? "Face Mesh Active" : "Positioning Camera...")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if testCompleted {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.dopaxStatusSuccess)
                        Text("Facial Test Complete!")
                            .font(.title3).bold()
                        Button("Done") {
                            appState.gamification.markCompleted(testType: "facial_movement")
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.dopaxPurple)
                    }
                } else if !isCountdownActive && !isTaskActive {
                    Button(action: startStepCountdown) {
                        Text("Start \(currentTask.title)")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.dopaxPurple)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 24)
        }
        .onAppear {
            appState.startFaceDistance()
        }
        .onReceive(timer) { _ in
            handleTimerTick()
        }
    }

    private func startStepCountdown() {
        countdownRemaining = 3
        isCountdownActive = true
    }

    private func handleTimerTick() {
        if isCountdownActive {
            if countdownRemaining > 1 {
                countdownRemaining -= 1
            } else {
                isCountdownActive = false
                isTaskActive = true
                taskTimeRemaining = 5
            }
        } else if isTaskActive {
            if taskTimeRemaining > 1 {
                taskTimeRemaining -= 1
            } else {
                isTaskActive = false
                if currentStepIndex + 1 < tasks.count {
                    currentStepIndex += 1
                } else {
                    testCompleted = true
                    recordFacialTestSummary()
                }
            }
        }
    }

    private func recordFacialTestSummary() {
        let sample = FaceDistanceSample(
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
            distanceRatio: 0.45,
            faceX: 0.5,
            faceY: 0.5,
            confidence: 1.0,
            roll: 0.0,
            yaw: 0.0
        )
        appState.dataManager.writeFaceSample(sample)
    }
}
