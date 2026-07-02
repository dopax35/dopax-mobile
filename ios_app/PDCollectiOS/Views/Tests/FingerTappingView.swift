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
    @State private var isPersonalBest = false
    @State private var trendMsg = ""
    @State private var leftFeatures:  PDAlgorithms.FingerTappingFeatures?
    @State private var rightFeatures: PDAlgorithms.FingerTappingFeatures?

    // Whack-a-mole state
    @State private var targetPosition: CGPoint = .zero
    @State private var canvasSize: CGSize = .zero
    @State private var hitPulse = false
    @State private var missPulse = false
    @State private var targetRadius: CGFloat = 52

    // Timing (Android-style: wall-clock start + monotonic elapsed)
    @State private var wallStartMs: Int64 = 0
    @State private var monoStartNs: UInt64 = 0

    private let duration = Constants.TestDuration.fingerTapping

    /// Wall-clock ms since epoch
    private static func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    /// Monotonic nanoseconds (immune to clock changes)
    private static func monoNs() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
    /// Elapsed ms since session start
    private func elapsedMs() -> Int64 { Int64((Self.monoNs() - monoStartMs) / 1_000_000) }
    @State private var monoStartMs: UInt64 = 0

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
                instructionRow(icon: "target", text: "A circle will appear on screen — tap it as fast as you can!")
                instructionRow(icon: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                               text: "Each tap makes it jump to a new random position")
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

    // MARK: - Running (Whack-a-mole)

    private var runningView: some View {
        VStack(spacing: 0) {
            // Header bar
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
                .tint(timeLeft < 3 ? .red : targetColor)

            // Count badge
            HStack {
                Spacer()
                Text("\(currentHand == .left ? leftCount : rightCount)")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(targetColor)
                    .contentTransition(.numericText())
                Text("taps").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 8)

            // Whack-a-mole canvas
            GeometryReader { geo in
                ZStack {
                    Color(.systemBackground)

                    // Miss zone — tap anywhere outside the circle to detect misses (optional UX)
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let dist = hypot(location.x - targetPosition.x,
                                            location.y - targetPosition.y)
                            if dist > targetRadius {
                                // Miss — shake
                                withAnimation(.default) { missPulse = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    missPulse = false
                                }
                            }
                        }

                    // The moving target circle
                    ZStack {
                        // Outer glow ring
                        Circle()
                            .stroke(targetColor.opacity(0.3), lineWidth: 8)
                            .frame(width: targetRadius * 2 + 16, height: targetRadius * 2 + 16)
                            .scaleEffect(hitPulse ? 1.4 : 1.0)
                            .opacity(hitPulse ? 0 : 1)
                            .animation(.easeOut(duration: 0.25), value: hitPulse)

                        // Main filled circle
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [targetColor.opacity(0.9), targetColor],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: targetRadius * 2, height: targetRadius * 2)
                            .shadow(color: targetColor.opacity(0.4), radius: 10)
                            .scaleEffect(hitPulse ? 0.7 : (missPulse ? 1.08 : 1.0))
                            .animation(hitPulse
                                ? .easeOut(duration: 0.15)
                                : .spring(response: 0.2, dampingFraction: 0.4),
                                       value: hitPulse || missPulse)

                        Image(systemName: "hand.point.up.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.9))
                            .scaleEffect(hitPulse ? 0.7 : 1.0)
                            .animation(.easeOut(duration: 0.15), value: hitPulse)
                    }
                    .position(targetPosition)
                    .onTapGesture {
                        handleHit()
                    }
                }
                .onAppear {
                    canvasSize = geo.size
                    // Only place if position is still zero (first time for this hand)
                    if targetPosition == .zero {
                        placeTargetRandom(in: geo.size)
                    }
                }
                .onChange(of: geo.size) { newSize in
                    canvasSize = newSize
                }
            }
        }
    }

    // MARK: - Result

    private var resultView: some View {
        ScrollView {
            VStack(spacing: 20) {
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

                VStack(spacing: 0) {
                    scoreSection("Left Hand", features: leftFeatures,
                                 count: leftCount, color: .blue)
                    Divider()
                    scoreSection("Right Hand", features: rightFeatures,
                                 count: rightCount, color: .green)
                }
                .cardStyle()

                asymmetryCard

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

    private var targetColor: Color { currentHand == .left ? .blue : .green }

    // MARK: - Logic

    private func startHand(_ hand: Hand) {
        timer?.invalidate(); timer = nil
        currentHand = hand
        timeLeft = duration
        hitPulse = false
        missPulse = false
        targetPosition = .zero
        phase = .running(hand: hand)

        // Record session start timestamps — matches Android MotorTestSession
        wallStartMs = Self.nowMs()
        monoStartMs = Self.monoNs()

        // Write START row
        let side = hand.rawValue
        appState.dataManager.writeFingerTappingRow(
            wallMs: wallStartMs, elapsedMs: 0,
            event: "START", buttonId: "",
            side: side, profile: appState.userProfile)

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            timeLeft -= 0.1
            if timeLeft <= 0 { finishHand(hand) }
        }
    }

    private func handleHit() {
        let now = Date()
        let side: String
        switch currentHand {
        case .left:
            leftCount += 1
            leftTimestamps.append(now)
            side = "Left"
        case .right:
            rightCount += 1
            rightTimestamps.append(now)
            side = "Right"
        }

        // Write SAMPLE row — matches Android finger_tapping.csv
        let wms = Self.nowMs()
        let ems = elapsedMs()
        appState.dataManager.writeFingerTappingRow(
            wallMs: wms, elapsedMs: ems,
            event: "SAMPLE", buttonId: side,
            side: side, profile: appState.userProfile)

        // Hit animation then jump
        withAnimation(.easeOut(duration: 0.12)) { hitPulse = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            hitPulse = false
            placeTargetRandom(in: canvasSize)
        }

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func placeTargetRandom(in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let pad = targetRadius + 12
        let newX = CGFloat.random(in: pad...(size.width - pad))
        let newY = CGFloat.random(in: pad...(size.height - pad))
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            targetPosition = CGPoint(x: newX, y: newY)
        }
    }

    private func finishHand(_ hand: Hand) {
        guard timer != nil else { return }
        timer?.invalidate(); timer = nil

        // Write END row
        let side = hand.rawValue
        appState.dataManager.writeFingerTappingRow(
            wallMs: Self.nowMs(), elapsedMs: elapsedMs(),
            event: "END", buttonId: "",
            side: side, profile: appState.userProfile)

        if hand == .left {
            leftFeatures = PDAlgorithms.fingerTappingFeatures(timestamps: leftTimestamps)
            phase = .between
        } else {
            rightFeatures = PDAlgorithms.fingerTappingFeatures(timestamps: rightTimestamps)
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
}
