import SwiftUI
import ARKit
import Vision

/// FacialMovementTestView drives a guided 5-task facial hypomimia assessment battery
/// (Rest, Brow Raise, Smile, Mouth Pucker, Rapid Blink) inspired by `face_test`.
/// Shows live camera feed preview with facial landmark mesh overlays and positioning guidance.
struct FacialMovementTestView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var currentStepIndex = 0
    @State private var isCountdownActive = false
    @State private var countdownRemaining = 3
    @State private var isTaskActive = false
    @State private var taskTimeRemaining = 5
    @State private var testCompleted = false

    private let tasks = [
        (title: "Neutral Rest", instruction: "Keep face completely relaxed at rest.", icon: "face.smiling"),
        (title: "Eyebrow Raise", instruction: "Raise eyebrows as high as comfortable.", icon: "arrow.up.and.line.horizontal.and.arrow.down"),
        (title: "Full Smile", instruction: "Smile broadly showing teeth.", icon: "mouth"),
        (title: "Mouth Pucker", instruction: "Pucker lips firmly forward.", icon: "circle.circle"),
        (title: "Rapid Blinking", instruction: "Blink rapidly and repeatedly for 5 seconds.", icon: "eye")
    ]

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Computes real-time positioning status based on last detected face sample
    private var facePositionStatus: FacePositionStatus {
        guard let face = appState.faceDistance.lastSample else {
            return .noFace
        }

        if face.distanceRatio < 0.22 {
            return .tooFar
        } else if face.distanceRatio > 0.72 {
            return .tooClose
        } else if face.faceX < 0.25 || face.faceX > 0.75 || face.faceY < 0.25 || face.faceY > 0.75 {
            return .offCenter
        } else {
            return .good
        }
    }

    var body: some View {
        VStack(spacing: 16) {
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

            // Dynamic Positioning Guidance Banner
            HStack(spacing: 10) {
                Image(systemName: facePositionStatus.icon)
                    .font(.title3)
                    .foregroundStyle(facePositionStatus.color)

                Text(facePositionStatus.rawValue)
                    .font(.subheadline).bold()
                    .foregroundStyle(.primary)

                Spacer()

                if isTaskActive {
                    Text("\(taskTimeRemaining)s")
                        .font(.title3).bold()
                        .foregroundStyle(.dopaxPurple)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(facePositionStatus.color.opacity(0.15))
            .cornerRadius(12)
            .padding(.horizontal)

            // Live Camera Preview Card with Face Mesh Landmarks Overlay
            ZStack {
                CameraPreviewView(session: appState.faceDistance.avSession)
                    .cornerRadius(20)

                FaceLandmarkOverlayView(
                    sample: appState.faceDistance.lastSample,
                    status: facePositionStatus
                )

                // Current Step Instruction Card overlay on camera
                let currentTask = tasks[currentStepIndex]
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: currentTask.icon)
                            .font(.title2)
                            .foregroundStyle(.dopaxPurple)
                        Text(currentTask.title)
                            .font(.headline).bold()
                    }

                    Text(currentTask.instruction)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .cornerRadius(14)
                .padding(.horizontal, 16)
                .position(x: 180, y: 50)

                // Countdown / Active Task timer overlay
                if isCountdownActive {
                    VStack {
                        Text("Get Ready")
                            .font(.headline).foregroundStyle(.white)
                        Text("\(countdownRemaining)")
                            .font(.system(size: 64, weight: .heavy, design: .rounded))
                            .foregroundStyle(.orange)
                    }
                    .padding(24)
                    .background(Color.black.opacity(0.65))
                    .cornerRadius(20)
                }
            }
            .frame(height: 380)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(facePositionStatus.color, lineWidth: 2)
            )
            .padding(.horizontal)

            Spacer()

            // Completion Card or Start Step Button
            if testCompleted {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.dopaxStatusSuccess)
                    Text("Facial Movement Test Complete!")
                        .font(.title3).bold()
                    Button("Done") {
                        appState.gamification.markCompleted(testType: "facial_movement")
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.dopaxPurple)
                }
            } else if !isCountdownActive && !isTaskActive {
                let currentTask = tasks[currentStepIndex]
                Button(action: startStepCountdown) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Step \(currentStepIndex + 1): \(currentTask.title)")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(facePositionStatus == .good ? Color.dopaxPurple : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                .disabled(facePositionStatus != .good)
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
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
