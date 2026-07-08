import SwiftUI

struct LegAgilityView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    private enum Phase { case instructions, running(side: Side), between, done }
    private enum Side: String { case left = "Left", right = "Right" }

    @State private var phase: Phase = .instructions
    @State private var timeLeft: Double = Constants.TestDuration.legAgility
    @State private var timer: Timer?
    @State private var leftReadings: [SensorReading] = []
    @State private var rightReadings: [SensorReading] = []
    @State private var leftFeatures: PDAlgorithms.LegAgilityFeatures?
    @State private var rightFeatures: PDAlgorithms.LegAgilityFeatures?
    @State private var currentSide: Side = .right // Android starts with Right Leg by default, or Left
    @State private var isPersonalBest = false
    @State private var trendMsg = ""

    // Timing (Android-style: wall-clock start + monotonic elapsed)
    @State private var wallStartMs: Int64 = 0
    @State private var monoStartMs: UInt64 = 0

    private let duration = Constants.TestDuration.legAgility

    // First-tested side (Right) is blue, second (Left) is purple — same ordinal
    // convention used by FingerTappingView/HandTurningView for their two sides.
    private var sideColor: Color { currentSide == .right ? .dopaxBlue : .dopaxPurple }

    private static func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    private static func monoNs() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
    private func elapsedMs() -> Int64 { Int64((Self.monoNs() - monoStartMs) / 1_000_000) }

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .instructions: instructionsView
            case .running:      runningView
            case .between:      betweenView
            case .done:         resultView
            }
        }
        .navigationTitle("Leg Agility")
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
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 64)).foregroundStyle(.dopaxBlue)
                .modifier(PulseModifier())

            Text("Leg Agility Test")
                .font(.title2).fontWeight(.bold)

            VStack(alignment: .leading, spacing: 12) {
                instructionRow(icon: "iphone.and.arrow.forward", text: "Hold phone firmly against your RIGHT thigh")
                instructionRow(icon: "figure.step.training", text: "Lift and stomp your foot as fast and as high as possible")
                instructionRow(icon: "clock", text: "Keep going for 10 seconds")
                instructionRow(icon: "arrow.left.and.right", text: "You will repeat for both legs")
            }
            .padding().background(.dopaxBlue.opacity(0.08)).cornerRadius(14)

            streakBanner

            Button("Start — Right Leg") { startLeg(.right) }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .tint(.dopaxBlue)
        }
        .padding()
    }

    // MARK: - Between Legs

    private var betweenView: some View {
        VStack(spacing: 24) {
            Image(systemName: "hands.clap.fill")
                .font(.system(size: 64)).foregroundStyle(.dopaxPurple)
                .modifier(PulseModifier())

            Text("Right leg done! 🎉")
                .font(.title2).fontWeight(.bold)
            if let f = rightFeatures {
                Text(String(format: "%d steps  ·  Freq %.2f Hz", f.nSteps, f.stepFreqHz))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Text("Now prepare for the LEFT leg…")
                .foregroundStyle(.secondary)

            Button("Start — Left Leg") { startLeg(.left) }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .tint(.dopaxPurple)
        }
        .padding()
    }

    // MARK: - Running

    private var runningView: some View {
        VStack(spacing: 24) {
            Spacer()

            Text(currentSide.rawValue + " Leg")
                .font(.title).fontWeight(.bold)
                .foregroundStyle(sideColor)

            Text(String(format: "%.1f s", timeLeft))
                .font(.system(size: 64, weight: .bold, design: .monospaced))
                .foregroundStyle(timeLeft < 3 ? .dopaxStatusError : .primary)

            ProgressView(value: duration - timeLeft, total: duration)
                .tint(timeLeft < 3 ? .dopaxStatusError : sideColor)
                .padding(.horizontal, 32)

            Spacer()

            // Live sensor activity indicator
            LiveTremorBar(magnitude: appState.motionManager.latestAccMagnitude)

            Spacer()
        }
    }

    // MARK: - Result

    private var resultView: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: isPersonalBest ? "trophy.fill" : "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(isPersonalBest ? .yellow : .dopaxStatusSuccess)
                        .modifier(PulseModifier())

                    Text(isPersonalBest ? "New Personal Best! 🏅" : "Test Complete")
                        .font(.title).fontWeight(.bold)

                    if !trendMsg.isEmpty {
                        Text(trendMsg).font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 0) {
                    scoreSection("Right Leg", features: rightFeatures, color: .dopaxBlue)
                    Divider()
                    scoreSection("Left Leg", features: leftFeatures, color: .dopaxPurple)
                }
                .cardStyle()

                asymmetryCard

                Text(appState.gamification.motivationalMessage)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(.dopaxOrange.opacity(0.08))
                    .cornerRadius(12)

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .tint(.dopaxBlue)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func scoreSection(_ title: String,
                               features: PDAlgorithms.LegAgilityFeatures?,
                               color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundStyle(color).padding(.bottom, 2)
            if let f = features {
                resultRow("Steps counted", "\(f.nSteps)")
                resultRow("Step Frequency", String(format: "%.2f Hz", f.stepFreqHz))
                resultRow("Rhythm CoV", String(format: "%.1f%%", f.rhythmCV),
                          note: f.rhythmCV > 25 ? "⚠️ irregular" : nil)
                resultRow("Lift Height (Mean)", String(format: "%.2f m/s²", f.liftMean))
                resultRow("Tremor Ratio", String(format: "%.3f", f.tremorPowerRatio),
                          note: f.tremorPowerRatio > 0.3 ? "⚠️ elevated" : nil)
                resultRow("Jerk RMS", String(format: "%.3f", f.jerkRMS))
            } else {
                resultRow("Steps counted", "0")
            }
        }
        .padding()
    }

    private var asymmetryCard: some View {
        let leftFreq = leftFeatures?.stepFreqHz ?? 0
        let rightFreq = rightFeatures?.stepFreqHz ?? 0
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
    private func resultRow(_ label: String, _ value: String, note: String? = nil) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
            if let n = note { Text(n).font(.caption).foregroundStyle(.dopaxOrange) }
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
            .background(.dopaxOrange.opacity(0.12)).cornerRadius(20)
        }
    }

    @ViewBuilder
    private func instructionRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.dopaxBlue)
            Text(text).font(.callout)
        }
    }

    // MARK: - Logic

    private func startLeg(_ side: Side) {
        currentSide = side
        timeLeft = duration
        wallStartMs = Self.nowMs()
        monoStartMs = Self.monoNs()

        // START row
        let sideStr = side == .left ? "Left" : "Right"
        appState.dataManager.writeLegAgilityRow(
            wallMs: wallStartMs, elapsedMs: 0, event: "START",
            gx: "", gy: "", gz: "", ax: "", ay: "", az: "",
            side: sideStr, profile: appState.userProfile)

        // Start motion at max rate and stream each sample to CSV immediately
        appState.motionManager.startStreaming { [self] r in
            let ems = Int64((Self.monoNs() - monoStartMs) / 1_000_000)
            let wms = wallStartMs + ems
            appState.dataManager.writeLegAgilityRow(
                wallMs: wms, elapsedMs: ems, event: "SAMPLE",
                gx: fmt6(r.gyroX), gy: fmt6(r.gyroY), gz: fmt6(r.gyroZ),
                ax: fmt6(r.accX),  ay: fmt6(r.accY),  az: fmt6(r.accZ),
                side: sideStr, profile: appState.userProfile)
        }

        phase = .running(side: side)
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            timeLeft -= 0.1
            if timeLeft <= 0 { finishLeg(side) }
        }
    }

    private func finishLeg(_ side: Side) {
        timer?.invalidate(); timer = nil
        let data = appState.motionManager.stopRecording()

        // END row
        let sideStr = side == .left ? "Left" : "Right"
        appState.dataManager.writeLegAgilityRow(
            wallMs: Self.nowMs(), elapsedMs: elapsedMs(), event: "END",
            gx: "", gy: "", gz: "", ax: "", ay: "", az: "",
            side: sideStr, profile: appState.userProfile)

        if side == .right {
            rightReadings = data
            rightFeatures = computeFeatures(data)
            phase = .between
        } else {
            leftReadings = data
            leftFeatures = computeFeatures(data)
            computeTrend()
            phase = .done
        }
    }

    private func computeFeatures(_ data: [SensorReading]) -> PDAlgorithms.LegAgilityFeatures? {
        let ax = data.map(\.accX); let ay = data.map(\.accY); let az = data.map(\.accZ)
        let gx = data.map(\.gyroX); let gy = data.map(\.gyroY); let gz = data.map(\.gyroZ)
        return PDAlgorithms.legAgilityFeatures(
            accX: ax, accY: ay, accZ: az,
            gyroX: gx, gyroY: gy, gyroZ: gz, hz: 100)
    }

    private func computeTrend() {
        let leftFreq = leftFeatures?.stepFreqHz ?? 0
        let rightFreq = rightFeatures?.stepFreqHz ?? 0
        let score = (leftFreq + rightFreq) / 2.0
        isPersonalBest = appState.gamification.isPersonalBest(
            testType: "leg_agility", score: score, higherIsBetter: true)
        trendMsg = appState.gamification.trendMessage(
            testType: "leg_agility", score: score, higherIsBetter: true)
        appState.gamification.recordCompletion(
            testType: "leg_agility", score: score, higherIsBetter: true)
    }

    private func fmt6(_ v: Double) -> String { String(format: "%.6f", v) }
}
