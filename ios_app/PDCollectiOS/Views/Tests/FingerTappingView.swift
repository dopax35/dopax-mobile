import SwiftUI

struct FingerTappingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    private enum Phase { case instructions, running(hand: Hand), between, done }
    private enum Hand: String { case left = "Left", right = "Right" }

    @State private var phase: Phase = .instructions
    @State private var leftTimestamps:  [Date] = []
    @State private var rightTimestamps: [Date] = []
    @State private var leftCount  = 0
    @State private var rightCount = 0
    @State private var currentHand: Hand = .left
    @State private var timeLeft: Double = Constants.TestDuration.fingerTapping
    @State private var timer: Timer?
    @State private var tapPulse = false
    @State private var leftFeatures:  PDAlgorithms.FingerTappingFeatures?
    @State private var rightFeatures: PDAlgorithms.FingerTappingFeatures?
    @State private var isPersonalBest = false
    @State private var trendMsg = ""

    private let duration = Constants.TestDuration.fingerTapping

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .instructions: instructionsView
            case .running:      runningView
            case .between:      betweenView
            case .done:         resultView
            }
        }
        .navigationTitle("Finger Tapping")
        .navigationBarBackButtonHidden(isRunning)
        .onDisappear { timer?.invalidate() }
    }

    private var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    // MARK: - Instructions

    private var instructionsView: some View {
        VStack(spacing: 24) {
            Image(systemName: "hand.point.up")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
                .modifier(PulseModifier())

            Text("Finger Tapping Test")
                .font(.title2).fontWeight(.bold)

            VStack(alignment: .leading, spacing: 12) {
                instructionRow(icon: "1.circle.fill", text: "Tap the big button as fast as you can")
                instructionRow(icon: "2.circle.fill", text: "Alternate index finger & thumb on the SAME hand")
                instructionRow(icon: "3.circle.fill", text: "Each hand gets 10 seconds")
            }
            .padding().background(.blue.opacity(0.08)).cornerRadius(14)

            streakBanner

            Button("Start — Left Hand") { startHand(.left) }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .tint(.blue)
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
                Text(String(format: "%.1f taps/sec  ·  CV %.2f", f.tapFrequencyHz, f.cvITI))
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
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(currentHand.rawValue + " Hand")
                    .font(.headline)
                Spacer()
                Text(String(format: "%.1f s", timeLeft))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(timeLeft < 3 ? .red : .primary)
            }
            .padding()

            ProgressView(value: (duration - timeLeft), total: duration)
                .tint(timeLeft < 3 ? .red : .blue)

            // Tap zone
            GeometryReader { geo in
                Button(action: handleTap) {
                    ZStack {
                        // Animated background pulse
                        Circle()
                            .fill(currentHand == .left ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
                            .scaleEffect(tapPulse ? 0.92 : 1.0)
                            .animation(.easeOut(duration: 0.08), value: tapPulse)
                            .frame(width: min(geo.size.width, geo.size.height) * 0.82)

                        VStack(spacing: 16) {
                            // Animated counter ring
                            ZStack {
                                Circle()
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 12)
                                    .frame(width: 140, height: 140)

                                let count = currentHand == .left ? leftCount : rightCount
                                Circle()
                                    .trim(from: 0, to: min(1, Double(count) / 40.0))
                                    .stroke(currentHand == .left ? Color.blue : Color.green,
                                            style: StrokeStyle(lineWidth: 12, lineCap: .round))
                                    .frame(width: 140, height: 140)
                                    .rotationEffect(.degrees(-90))
                                    .animation(.easeOut(duration: 0.1), value: count)

                                VStack(spacing: 2) {
                                    Text("\(count)")
                                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                                        .contentTransition(.numericText())
                                    Text("taps")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }

                            Text("TAP HERE")
                                .font(.title2).fontWeight(.heavy)
                                .foregroundStyle(currentHand == .left ? .blue : .green)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .buttonStyle(.plain)
            }
        }
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

                // Score cards
                VStack(spacing: 0) {
                    scoreSection("Left Hand", features: leftFeatures,
                                 count: leftCount, color: .blue)
                    Divider()
                    scoreSection("Right Hand", features: rightFeatures,
                                 count: rightCount, color: .green)
                }
                .cardStyle()

                // Asymmetry card
                asymmetryCard

                // Motivational message
                Text(appState.gamification.motivationalMessage)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(.orange.opacity(0.08))
                    .cornerRadius(12)

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func scoreSection(_ title: String,
                               features: PDAlgorithms.FingerTappingFeatures?,
                               count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundStyle(color).padding(.bottom, 2)
            resultRow("Taps", "\(count)")
            if let f = features {
                resultRow("Rate", String(format: "%.1f taps/s", f.tapFrequencyHz))
                resultRow("Rhythm CoV", String(format: "%.3f", f.cvITI),
                          note: f.cvITI > 0.25 ? "⚠️ irregular" : nil)
                resultRow("Decrement", String(format: "%.4f", f.itiSlope),
                          note: f.itiSlope > 0.002 ? "⚠️ slowing" : nil)
                if f.hesitationCount > 0 {
                    resultRow("Hesitations", "\(f.hesitationCount)", note: "⚠️")
                }
            }
        }
        .padding()
    }

    private var asymmetryCard: some View {
        let leftRate  = Double(leftCount)  / duration
        let rightRate = Double(rightCount) / duration
        let ai = PDAlgorithms.asymmetryIndex(left: leftRate, right: rightRate)
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
            Image(systemName: icon).foregroundStyle(.blue)
            Text(text).font(.callout)
        }
    }

    // MARK: - Logic

    private func startHand(_ hand: Hand) {
        currentHand = hand
        timeLeft = duration
        phase = .running(hand: hand)

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            timeLeft -= 0.1
            if timeLeft <= 0 { finishHand(hand) }
        }
    }

    private func handleTap() {
        let now = Date()
        switch currentHand {
        case .left:
            leftCount += 1
            leftTimestamps.append(now)
        case .right:
            rightCount += 1
            rightTimestamps.append(now)
        }
        // Animate pulse
        tapPulse = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { tapPulse = false }
    }

    private func finishHand(_ hand: Hand) {
        timer?.invalidate(); timer = nil

        if hand == .left {
            leftFeatures = PDAlgorithms.fingerTappingFeatures(timestamps: leftTimestamps)
            saveResult(hand: .left, count: leftCount, features: leftFeatures)
            phase = .between
        } else {
            rightFeatures = PDAlgorithms.fingerTappingFeatures(timestamps: rightTimestamps)
            saveResult(hand: .right, count: rightCount, features: rightFeatures)
            computeTrend()
            phase = .done
        }
    }

    private func computeTrend() {
        let score = (Double(leftCount) + Double(rightCount)) / (2 * duration)
        isPersonalBest = appState.gamification.isPersonalBest(
            testType: "finger_tapping", score: score, higherIsBetter: true)
        trendMsg = appState.gamification.trendMessage(
            testType: "finger_tapping", score: score, higherIsBetter: true)
        appState.gamification.recordCompletion(
            testType: "finger_tapping", score: score, higherIsBetter: true)
    }

    private func saveResult(hand: Hand, count: Int,
                            features: PDAlgorithms.FingerTappingFeatures?) {
        var details = "taps:\(count)"
        if let f = features {
            details += String(format: ",freq:%.3f,cv:%.4f,slope:%.5f,hesitations:\(f.hesitationCount)",
                              f.tapFrequencyHz, f.cvITI, f.itiSlope)
        }
        let result = TestResult(
            timestamp: Date(),
            testType: .fingerTapping,
            part: hand.rawValue,
            score: features?.tapFrequencyHz ?? Double(count) / duration,
            durationMs: Int(duration * 1000),
            errors: features?.hesitationCount ?? 0,
            details: details
        )
        appState.dataManager.writeTestResult(result)
    }
}
