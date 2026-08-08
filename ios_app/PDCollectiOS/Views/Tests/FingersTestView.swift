import SwiftUI
import AVFoundation
import Vision

/// Free-space camera-based finger movement test from `fingers_test`.
/// Shows live camera feed preview with Vision hand landmark overlays (thumb & index tip points, pinch distance line)
/// and real-time positioning guidance for optimal camera placement.
struct FingersTestView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var handTracker = HandTrackingManager()

    @State private var isCountdownRunning = false
    @State private var countdownRemaining = 3
    @State private var isTestRunning = false
    @State private var timeRemaining = 10
    @State private var testCompleted = false
    @State private var currentHand = "Right"

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Free-Space Fingers Test")
                    .font(.title2).bold()
                Spacer()
                Text("Vision Hand Tracking")
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.dopaxBlue.opacity(0.15))
                    .cornerRadius(8)
            }
            .padding(.horizontal)

            // Positioning Guidance Banner
            HStack(spacing: 10) {
                Image(systemName: handTracker.positionStatus.icon)
                    .font(.title3)
                    .foregroundStyle(handTracker.positionStatus.color)

                Text(handTracker.positionStatus.rawValue)
                    .font(.subheadline).bold()
                    .foregroundStyle(.primary)

                Spacer()

                if isTestRunning {
                    Text("\(timeRemaining)s")
                        .font(.title3).bold()
                        .foregroundStyle(.dopaxBlue)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(handTracker.positionStatus.color.opacity(0.15))
            .cornerRadius(12)
            .padding(.horizontal)

            // Live Camera Preview Card with Hand Landmarks Overlay
            ZStack {
                CameraPreviewView(session: handTracker.session)
                    .cornerRadius(20)

                HandLandmarkOverlayView(
                    landmarks: handTracker.currentHandmarks,
                    status: handTracker.positionStatus
                )

                // Overlaid Instructions / Countdown / Running Counters
                if isCountdownRunning {
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
                } else if isTestRunning {
                    VStack(spacing: 4) {
                        Text("Taps Detected")
                            .font(.caption).foregroundStyle(.white.opacity(0.8))
                        Text("\(handTracker.tapCount)")
                            .font(.system(size: 48, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Color.black.opacity(0.65))
                    .cornerRadius(16)
                    .position(x: 80, y: 50)
                } else if !testCompleted {
                    VStack(spacing: 8) {
                        Text("Tap thumb and index fingertips together repeatedly as fast and wide as possible.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .padding(.horizontal)
                    }
                    .padding(14)
                    .background(Color.black.opacity(0.65))
                    .cornerRadius(14)
                    .padding(.horizontal, 20)
                    .position(x: 200, y: 40)
                }
            }
            .frame(height: 380)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(handTracker.positionStatus.color, lineWidth: 2)
            )
            .padding(.horizontal)

            Spacer()

            // Completion Card or Start Button
            if testCompleted {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.dopaxStatusSuccess)
                    Text("Fingers Test Complete!")
                        .font(.title3).bold()
                    Text("Recorded \(handTracker.tapCount) taps in free space")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Done") {
                        appState.gamification.markCompleted(testType: "fingers_test")
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.dopaxBlue)
                }
            } else if !isCountdownRunning && !isTestRunning {
                Button(action: startCountdown) {
                    HStack {
                        Image(systemName: "hand.tap.fill")
                        Text("Start \(currentHand) Hand Test")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(handTracker.positionStatus == .good ? Color.dopaxBlue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                .disabled(handTracker.positionStatus != .good)
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .onAppear {
            handTracker.startTracking()
        }
        .onDisappear {
            handTracker.stopTracking()
        }
        .onReceive(timer) { _ in
            handleTick()
        }
    }

    private func startCountdown() {
        handTracker.resetTapCount()
        countdownRemaining = 3
        isCountdownRunning = true
    }

    private func handleTick() {
        if isCountdownRunning {
            if countdownRemaining > 1 {
                countdownRemaining -= 1
            } else {
                isCountdownRunning = false
                isTestRunning = true
                timeRemaining = 10
            }
        } else if isTestRunning {
            if timeRemaining > 1 {
                timeRemaining -= 1
            } else {
                isTestRunning = false
                testCompleted = true
                writeFingersTestData()
            }
        }
    }

    private func writeFingersTestData() {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let row = "\(timestamp),10000,END,\(currentHand),\(handTracker.tapCount),0,0,0,0,0,0.85,1.42\n"
        appState.dataManager.writeFingersTestData(row)
    }
}
