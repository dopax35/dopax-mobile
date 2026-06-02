import SwiftUI

struct HandTurningView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    private enum Phase { case instructions, running, done }

    @State private var phase: Phase = .instructions
    @State private var timeLeft: Double = Constants.TestDuration.handTurning
    @State private var timer: Timer?
    @State private var readings: [SensorReading] = []
    @State private var features: PDAlgorithms.HandTurningFeatures?
    @State private var isPersonalBest = false
    @State private var trendMsg = ""

    private let duration = Constants.TestDuration.handTurning

    var body: some View {
        VStack {
            switch phase {
            case .instructions: instructionsView
            case .running:      runningView
            case .done:         resultView
            }
        }
        .navigationTitle("Hand Turning")
        .navigationBarBackButtonHidden(phase == .running)
        .onDisappear {
            timer?.invalidate()
            _ = appState.motionManager.stopRecording()
        }
    }

    // MARK: - Instructions

    private var instructionsView: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 64)).foregroundStyle(.green)
                .modifier(PulseModifier())

            Text("Hand Turning Test")
                .font(.title2).fontWeight(.bold)

            VStack(alignment: .leading, spacing: 12) {
                instructionRow(icon: "iphone", text: "Hold phone in your affected hand, screen facing up")
                instructionRow(icon: "arrow.clockwise.circle", text: "Rotate palm UP then DOWN repeatedly")
                instructionRow(icon: "clock", text: "Keep going for 10 seconds — as fast as possible")
            }
            .padding().background(.green.opacity(0.08)).cornerRadius(14)

            streakBanner

            Button("Start Test") { startTest() }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .tint(.green)
        }
        .padding()
    }

    // MARK: - Running

    private var runningView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Countdown ring
            ZStack {
                Circle()
                    .stroke(Color.green.opacity(0.15), lineWidth: 14)
                    .frame(width: 200, height: 200)

                Circle()
                    .trim(from: 0, to: CGFloat((duration - timeLeft) / duration))
                    .stroke(timeLeft < 3 ? Color.red : Color.green,
                            style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: timeLeft)

                VStack(spacing: 6) {
                    Text(String(format: "%.1f", timeLeft))
                        .font(.system(size: 56, weight: .bold, design: .monospaced))
                        .foregroundStyle(timeLeft < 3 ? .red : .primary)
                    Text("seconds").foregroundStyle(.secondary)
                }
            }

            Text("Keep rotating your hand!")
                .font(.title2).fontWeight(.semibold)
                .foregroundStyle(.green)

            // Live gyro visualisation
            LiveGyroArc(gyroZ: appState.motionManager.latestGyroZ)

            // Live tremor signal bar
            LiveTremorBar(magnitude: appState.motionManager.latestAccMagnitude)

            Spacer()
        }
        .padding()
    }

    // MARK: - Result

    private var resultView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: isPersonalBest ? "trophy.fill" : "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(isPersonalBest ? .yellow : .green)
                    .modifier(PulseModifier())

                Text(isPersonalBest ? "New Personal Best! 🏅" : "Test Complete")
                    .font(.title).fontWeight(.bold)
                if !trendMsg.isEmpty {
                    Text(trendMsg).font(.subheadline).foregroundStyle(.secondary)
                }

                // Core metrics card
                VStack(spacing: 8) {
                    resultRow("Duration", "\(Int(duration)) seconds")
                    if let f = features {
                        resultRow("Turning Speed (RMS)",
                                  String(format: "%.2f rad/s", f.turningSpeedRMS))
                        resultRow("Turning Speed (Max)",
                                  String(format: "%.2f rad/s", f.turningSpeedMax))
                        resultRow("Frequency",
                                  String(format: "%.2f Hz", f.turningFreqHz))
                        resultRow("Rhythm CoV",
                                  String(format: "%.1f%%", f.rhythmCV),
                                  note: f.rhythmCV > 25 ? "⚠️ irregular" : nil)
                        resultRow("Amplitude Decay",
                                  String(format: "%.4f", f.amplitudeDecay),
                                  note: f.amplitudeDecay < -0.05 ? "⚠️ fatigue" : nil)
                        resultRow("Tremor Ratio",
                                  String(format: "%.3f", f.tremorPowerRatio),
                                  note: f.tremorPowerRatio > 0.3 ? "⚠️ elevated" : nil)
                        resultRow("Jerk RMS",
                                  String(format: "%.3f", f.jerkRMS))
                    }
                }
                .cardStyle()

                // Pronation/Supination Asymmetry
                if let f = features {
                    pronoSupraCard(f.pronoSupraAsymmetry)
                }

                Text(appState.gamification.motivationalMessage)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(.green.opacity(0.08))
                    .cornerRadius(12)

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .tint(.green)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func pronoSupraCard(_ ratio: Double) -> some View {
        let deviation = abs(ratio - 1.0)
        let color: Color = deviation < 0.15 ? .green : (deviation < 0.35 ? .yellow : .orange)
        VStack(spacing: 8) {
            HStack {
                Text("Prono/Supra Asymmetry").font(.headline)
                Spacer()
                Text(String(format: "%.2f", ratio))
                    .font(.title3.bold()).foregroundStyle(color)
            }
            Text("1.0 = perfectly symmetric pronation & supination")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding().cardStyle()
    }

    @ViewBuilder
    private func resultRow(_ label: String, _ value: String, note: String? = nil) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
            if let n = note { Text(n).font(.caption).foregroundStyle(.orange) }
        }
    }

    @ViewBuilder
    private var streakBanner: some View {
        let s = appState.gamification.currentStreak
        if s > 0 {
            HStack(spacing: 8) {
                Text(appState.gamification.streakEmoji).font(.title2)
                Text("\(s)-day streak!").fontWeight(.semibold)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(.orange.opacity(0.12)).cornerRadius(20)
        }
    }

    @ViewBuilder
    private func instructionRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.green)
            Text(text).font(.callout)
        }
    }

    // MARK: - Logic

    private func startTest() {
        appState.motionManager.startRecording()
        phase = .running
        timeLeft = duration

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            timeLeft -= 0.1
            if timeLeft <= 0 {
                timer?.invalidate(); timer = nil
                let data = appState.motionManager.stopRecording()
                readings = data
                computeFeatures(data)
                saveResult()
                phase = .done
            }
        }
    }

    private func computeFeatures(_ data: [SensorReading]) {
        let gx = data.map(\.gyroX); let gy = data.map(\.gyroY); let gz = data.map(\.gyroZ)
        features = PDAlgorithms.handTurningFeatures(
            gyroX: gx, gyroY: gy, gyroZ: gz, hz: 100)
        if let f = features {
            isPersonalBest = appState.gamification.isPersonalBest(
                testType: "hand_turning", score: f.turningFreqHz, higherIsBetter: true)
            trendMsg = appState.gamification.trendMessage(
                testType: "hand_turning", score: f.turningFreqHz, higherIsBetter: true)
            appState.gamification.recordCompletion(
                testType: "hand_turning", score: f.turningFreqHz, higherIsBetter: true)
        }
    }

    private func saveResult() {
        appState.dataManager.writeSensorReadings(readings)
        var details = "samples:\(readings.count)"
        if let f = features {
            details += String(format: ",rms:%.3f,freq:%.3f,rhythm_cv:%.2f,tremor:%.4f,prono_asym:%.4f",
                              f.turningSpeedRMS, f.turningFreqHz,
                              f.rhythmCV, f.tremorPowerRatio, f.pronoSupraAsymmetry)
        }
        let result = TestResult(
            timestamp: Date(),
            testType: .handTurning,
            part: "affected",
            score: features?.turningFreqHz ?? 0,
            durationMs: Int(duration * 1000),
            errors: 0,
            details: details
        )
        appState.dataManager.writeTestResult(result)
    }
}

// MARK: - Live Gyro Arc

private struct LiveGyroArc: View {
    let gyroZ: Double

    var body: some View {
        VStack(spacing: 4) {
            Text("Rotation signal").font(.caption).foregroundStyle(.secondary)
            ZStack {
                // Background arc
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(Color(.systemGray5), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(90))

                // Signal arc
                let fraction = min(abs(gyroZ) / 8.0, 0.7)
                Circle()
                    .trim(from: 0.15, to: 0.15 + fraction)
                    .stroke(gyroZ > 0 ? Color.blue : Color.orange,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(90))
                    .animation(.easeOut(duration: 0.05), value: gyroZ)

                Text(String(format: "%.1f", abs(gyroZ)))
                    .font(.caption.monospacedDigit())
            }
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Live Tremor Bar

private struct LiveTremorBar: View {
    let magnitude: Double

    var body: some View {
        VStack(spacing: 4) {
            Text("Movement intensity").font(.caption).foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 14)
                    Capsule()
                        .fill(magnitude > 2.0 ? Color.orange : Color.green)
                        .frame(width: geo.size.width * min(magnitude / 4.0, 1.0), height: 14)
                        .animation(.easeOut(duration: 0.05), value: magnitude)
                }
            }
            .frame(height: 14)
        }
        .padding(.horizontal, 32)
    }
}
