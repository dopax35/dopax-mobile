import SwiftUI

struct HandTurningView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    private enum Phase { case instructions, running(hand: Hand), between, done }
    private enum Hand: String { case left = "Left", right = "Right" }

    @State private var phase: Phase = .instructions
    @State private var timeLeft: Double = Constants.TestDuration.handTurning
    @State private var timer: Timer?
    @State private var leftReadings: [SensorReading] = []
    @State private var rightReadings: [SensorReading] = []
    @State private var leftFeatures: PDAlgorithms.HandTurningFeatures?
    @State private var rightFeatures: PDAlgorithms.HandTurningFeatures?
    @State private var currentHand: Hand = .left
    @State private var isPersonalBest = false
    @State private var trendMsg = ""

    // Android-compatible timing
    @State private var wallStartMs: Int64 = 0
    @State private var monoStartMs: UInt64 = 0

    private static func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    private static func monoNs() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
    private func elapsedMs() -> Int64 { Int64((Self.monoNs() - monoStartMs) / 1_000_000) }

    private let duration = Constants.TestDuration.handTurning

    var body: some View {
        VStack {
            switch phase {
            case .instructions: instructionsView
            case .running:      runningView
            case .between:      betweenView
            case .done:         resultView
            }
        }
        .navigationTitle("Hand Turning")
        .navigationBarBackButtonHidden(isRunning)
        .onDisappear {
            timer?.invalidate()
            _ = appState.motionManager.stopRecording()
        }
    }

    private var isRunning: Bool {
        if case .running = phase { return true }
        return false
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
                instructionRow(icon: "iphone", text: "Hold phone in your LEFT hand, screen facing up")
                instructionRow(icon: "arrow.clockwise.circle", text: "Rotate palm UP then DOWN repeatedly")
                instructionRow(icon: "clock", text: "Keep going for 10 seconds — as fast as possible")
            }
            .padding().background(.green.opacity(0.08)).cornerRadius(14)

            streakBanner

            Button("Start — Left Hand") { startHand(.left) }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .tint(.green)
        }
        .padding()
    }

    // MARK: - Between hands

    private var betweenView: some View {
        VStack(spacing: 24) {
            Image(systemName: "hands.clap.fill")
                .font(.system(size: 64)).foregroundStyle(.green)
                .modifier(PulseModifier())

            Text("Left hand done! 🎉")
                .font(.title2).fontWeight(.bold)
            if let f = leftFeatures {
                Text(String(format: "%.2f Hz  ·  CV %.1f%%", f.turningFreqHz, f.rhythmCV))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Text("Get ready with your RIGHT hand…")
                .foregroundStyle(.secondary)

            Button("Start — Right Hand") { startHand(.right) }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .tint(.green)
        }
        .padding()
    }

    // MARK: - Running

    private var runningView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Hand indicator
            Text(currentHand.rawValue + " Hand")
                .font(.headline)

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
                // Trophy / completion header
                VStack(spacing: 8) {
                    Image(systemName: isPersonalBest ? "trophy.fill" : "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(isPersonalBest ? .yellow : .green)
                        .modifier(PulseModifier())

                    Text(isPersonalBest ? "New Personal Best! 🏅" : "Test Complete")
                        .font(.title).fontWeight(.bold)

                    if !trendMsg.isEmpty {
                        Text(trendMsg)
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                // Score cards – Left & Right side by side
                VStack(spacing: 0) {
                    scoreSection("Left Hand", features: leftFeatures, color: .blue)
                    Divider()
                    scoreSection("Right Hand", features: rightFeatures, color: .green)
                }
                .cardStyle()

                // Asymmetry card comparing left vs right turning frequency
                asymmetryCard

                // Pronation/Supination cards per hand
                if let f = leftFeatures {
                    pronoSupraCard("Left Prono/Supra", f.pronoSupraAsymmetry)
                }
                if let f = rightFeatures {
                    pronoSupraCard("Right Prono/Supra", f.pronoSupraAsymmetry)
                }

                // Motivational message
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
    private func scoreSection(_ title: String,
                               features: PDAlgorithms.HandTurningFeatures?,
                               color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundStyle(color).padding(.bottom, 2)
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
        .padding()
    }

    private var asymmetryCard: some View {
        let leftFreq  = leftFeatures?.turningFreqHz ?? 0
        let rightFreq = rightFeatures?.turningFreqHz ?? 0
        let ai = PDAlgorithms.asymmetryIndex(left: leftFreq, right: rightFreq)
        let color: Color = ai < 10 ? .green : (ai < 20 ? .yellow : .orange)

        return VStack(spacing: 8) {
            HStack {
                Text("Side Asymmetry").font(.headline)
                Spacer()
                Text(String(format: "%.1f%%", ai))
                    .font(.title3.bold())
                    .foregroundStyle(color)
            }
            // Visual bar
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 10)
                    Capsule().fill(color)
                        .frame(width: g.size.width * min(ai / 50.0, 1.0), height: 10)
                        .animation(.easeOut(duration: 0.6), value: ai)
                }
            }
            .frame(height: 10)
            Text("< 10% symmetric · 10–20% mild · > 20% clinically notable")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .cardStyle()
    }

    @ViewBuilder
    private func pronoSupraCard(_ title: String, _ ratio: Double) -> some View {
        let deviation = abs(ratio - 1.0)
        let color: Color = deviation < 0.15 ? .green : (deviation < 0.35 ? .yellow : .orange)
        VStack(spacing: 8) {
            HStack {
                Text(title).font(.headline)
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

    private func startHand(_ hand: Hand) {
        currentHand = hand
        timeLeft = duration
        wallStartMs = Self.nowMs()
        monoStartMs = Self.monoNs()

        // START row
        let side = hand.rawValue
        appState.dataManager.writeHandTurningRow(
            wallMs: wallStartMs, elapsedMs: 0, event: "START",
            gx: "", gy: "", gz: "", ax: "", ay: "", az: "",
            side: side, profile: appState.userProfile)

        // Start motion at max rate and stream each sample to CSV immediately
        appState.motionManager.startStreaming { [self] r in
            let ems = Int64((Self.monoNs() - monoStartMs) / 1_000_000)
            let wms = wallStartMs + ems
            appState.dataManager.writeHandTurningRow(
                wallMs: wms, elapsedMs: ems, event: "SAMPLE",
                gx: fmt6(r.gyroX), gy: fmt6(r.gyroY), gz: fmt6(r.gyroZ),
                ax: fmt6(r.accX),  ay: fmt6(r.accY),  az: fmt6(r.accZ),
                side: side, profile: appState.userProfile)
        }

        phase = .running(hand: hand)
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            timeLeft -= 0.1
            if timeLeft <= 0 { finishHand(hand) }
        }
    }

    private func finishHand(_ hand: Hand) {
        timer?.invalidate(); timer = nil
        let data = appState.motionManager.stopRecording()

        // END row
        let side = hand.rawValue
        appState.dataManager.writeHandTurningRow(
            wallMs: Self.nowMs(), elapsedMs: elapsedMs(), event: "END",
            gx: "", gy: "", gz: "", ax: "", ay: "", az: "",
            side: side, profile: appState.userProfile)

        if hand == .left {
            leftReadings = data
            leftFeatures = computeFeatures(data)
            phase = .between
        } else {
            rightReadings = data
            rightFeatures = computeFeatures(data)
            computeTrend()
            phase = .done
        }
    }

    private func computeFeatures(_ data: [SensorReading]) -> PDAlgorithms.HandTurningFeatures {
        let gx = data.map(\.gyroX); let gy = data.map(\.gyroY); let gz = data.map(\.gyroZ)
        return PDAlgorithms.handTurningFeatures(
            gyroX: gx, gyroY: gy, gyroZ: gz, hz: 100)
    }

    private func computeTrend() {
        let leftFreq = leftFeatures?.turningFreqHz ?? 0
        let rightFreq = rightFeatures?.turningFreqHz ?? 0
        let score = (leftFreq + rightFreq) / 2.0
        isPersonalBest = appState.gamification.isPersonalBest(
            testType: "hand_turning", score: score, higherIsBetter: true)
        trendMsg = appState.gamification.trendMessage(
            testType: "hand_turning", score: score, higherIsBetter: true)
        appState.gamification.recordCompletion(
            testType: "hand_turning", score: score, higherIsBetter: true)
    }

    private func fmt6(_ v: Double) -> String { String(format: "%.6f", v) }
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

struct LiveTremorBar: View {
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
