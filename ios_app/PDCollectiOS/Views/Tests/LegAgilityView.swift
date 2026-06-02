import SwiftUI

struct LegAgilityView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    private enum Phase { case instructions, running, done }
    private enum Side { case left, right }

    @State private var phase: Phase = .instructions
    @State private var activeZone: Side = .left
    @State private var leftCount  = 0
    @State private var rightCount = 0
    @State private var leftTimestamps:  [Date] = []
    @State private var rightTimestamps: [Date] = []
    @State private var timeLeft: Double = Constants.TestDuration.legAgility
    @State private var timer: Timer?
    @State private var comboCount = 0          // consecutive correct taps
    @State private var showCombo = false
    @State private var isPersonalBest = false
    @State private var trendMsg = ""

    private let duration = Constants.TestDuration.legAgility

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .instructions: instructionsView
            case .running:      runningView
            case .done:         resultView
            }
        }
        .navigationTitle("Leg Agility")
        .navigationBarBackButtonHidden(phase == .running)
        .onDisappear { timer?.invalidate() }
    }

    // MARK: - Instructions

    private var instructionsView: some View {
        VStack(spacing: 24) {
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 64)).foregroundStyle(.red)
                .modifier(PulseModifier())

            Text("Leg Agility Test")
                .font(.title2).fontWeight(.bold)

            VStack(alignment: .leading, spacing: 12) {
                instructionRow(icon: "iphone.and.arrow.forward", text: "Place phone flat on table or hold it")
                instructionRow(icon: "arrow.left.arrow.right", text: "Tap the HIGHLIGHTED side with that heel")
                instructionRow(icon: "figure.step.training", text: "Lift heel fully between each tap")
                instructionRow(icon: "clock", text: "Alternate heels for 10 seconds")
            }
            .padding().background(.red.opacity(0.08)).cornerRadius(14)

            streakBanner

            Button("Start Test") { startTest() }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .tint(.red)
        }
        .padding()
    }

    // MARK: - Running

    private var runningView: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("Leg Agility")
                    .font(.headline)
                Spacer()
                // Combo indicator
                if showCombo {
                    Text("Combo x\(comboCount)!")
                        .font(.caption.bold())
                        .foregroundStyle(.yellow)
                        .transition(.scale.combined(with: .opacity))
                }
                Text(String(format: "%.1f s", timeLeft))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(timeLeft < 3 ? .red : .primary)
            }
            .padding()
            .animation(.easeInOut(duration: 0.2), value: showCombo)

            ProgressView(value: duration - timeLeft, total: duration)
                .tint(timeLeft < 3 ? .red : .red.opacity(0.7))

            GeometryReader { geo in
                HStack(spacing: 0) {
                    tapZone(side: .left, size: geo.size)
                    Divider()
                    tapZone(side: .right, size: geo.size)
                }
            }
        }
    }

    @ViewBuilder
    private func tapZone(side: Side, size: CGSize) -> some View {
        let isActive = activeZone == side
        let count = side == .left ? leftCount : rightCount
        Button(action: { handleTap(side: side) }) {
            ZStack {
                (isActive ? Color.red.opacity(0.25) : Color(.systemGray6))
                    .animation(.easeInOut(duration: 0.1), value: isActive)

                VStack(spacing: 12) {
                    // Foot icon with pulse
                    ZStack {
                        if isActive {
                            Circle()
                                .fill(Color.red.opacity(0.2))
                                .frame(width: 100, height: 100)
                                .scaleEffect(isActive ? 1.05 : 1.0)
                                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                                           value: isActive)
                        }
                        Text(side == .left ? "L" : "R")
                            .font(.system(size: 72, weight: .heavy))
                            .foregroundStyle(isActive ? .red : .gray)
                    }

                    if isActive {
                        Text("TAP!")
                            .font(.headline.bold())
                            .foregroundStyle(.red)
                            .transition(.scale)
                    }

                    // Counter with animation
                    Text("\(count)")
                        .font(.title).fontWeight(.bold)
                        .contentTransition(.numericText())
                        .foregroundStyle(isActive ? .red : .secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: size.width / 2, height: size.height)
    }

    // MARK: - Result

    private var resultView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: isPersonalBest ? "trophy.fill" : "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(isPersonalBest ? .yellow : .red)
                    .modifier(PulseModifier())

                Text(isPersonalBest ? "New Personal Best! 🏅" : "Test Complete")
                    .font(.title).fontWeight(.bold)
                if !trendMsg.isEmpty {
                    Text(trendMsg).font(.subheadline).foregroundStyle(.secondary)
                }

                // Score card
                VStack(spacing: 8) {
                    resultRow("Left Taps",  "\(leftCount)")
                    resultRow("Right Taps", "\(rightCount)")
                    resultRow("Total",      "\(leftCount + rightCount)")
                    resultRow("Rate", String(format: "%.1f taps/s",
                                            Double(leftCount + rightCount) / duration))

                    if !leftTimestamps.isEmpty, !rightTimestamps.isEmpty {
                        let leftRate  = Double(leftCount)  / duration
                        let rightRate = Double(rightCount) / duration

                        // ITI stats per side
                        if let lf = PDAlgorithms.fingerTappingFeatures(timestamps: leftTimestamps),
                           let rf = PDAlgorithms.fingerTappingFeatures(timestamps: rightTimestamps) {
                            Divider()
                            resultRow("Left Rhythm CoV",  String(format: "%.3f", lf.cvITI),
                                      note: lf.cvITI > 0.25 ? "⚠️" : nil)
                            resultRow("Right Rhythm CoV", String(format: "%.3f", rf.cvITI),
                                      note: rf.cvITI > 0.25 ? "⚠️" : nil)
                        }
                    }
                }
                .cardStyle()

                // Asymmetry card
                asymmetryCard

                Text(appState.gamification.motivationalMessage)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(.red.opacity(0.08))
                    .cornerRadius(12)

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .tint(.red)
            }
            .padding()
        }
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
                    .font(.title3.bold()).foregroundStyle(color)
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
            HStack {
                Text("Left: \(String(format: "%.1f", leftRate)) t/s")
                Spacer()
                Text("Right: \(String(format: "%.1f", rightRate)) t/s")
            }
            .font(.caption).foregroundStyle(.secondary)
            Text("< 10% symmetric · 10–20% mild · > 20% clinically notable")
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
            Image(systemName: icon).foregroundStyle(.red)
            Text(text).font(.callout)
        }
    }

    // MARK: - Logic

    private func startTest() {
        leftCount = 0; rightCount = 0
        leftTimestamps = []; rightTimestamps = []
        activeZone = .left; comboCount = 0
        timeLeft = duration; phase = .running

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            timeLeft -= 0.1
            if timeLeft <= 0 { finishTest() }
        }
    }

    private func handleTap(side: Side) {
        guard activeZone == side else {
            // Wrong side — reset combo
            comboCount = 0; showCombo = false
            return
        }
        let now = Date()
        switch side {
        case .left:
            leftCount += 1
            leftTimestamps.append(now)
            activeZone = .right
        case .right:
            rightCount += 1
            rightTimestamps.append(now)
            activeZone = .left
        }
        // Combo tracking
        comboCount += 1
        if comboCount >= 5 {
            withAnimation { showCombo = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation { showCombo = false }
            }
        }
    }

    private func finishTest() {
        timer?.invalidate(); timer = nil
        let score = Double(leftCount + rightCount) / duration
        isPersonalBest = appState.gamification.isPersonalBest(
            testType: "leg_agility", score: score, higherIsBetter: true)
        trendMsg = appState.gamification.trendMessage(
            testType: "leg_agility", score: score, higherIsBetter: true)
        appState.gamification.recordCompletion(
            testType: "leg_agility", score: score, higherIsBetter: true)
        phase = .done
        saveResult()
    }

    private func saveResult() {
        let ai = PDAlgorithms.asymmetryIndex(
            left:  Double(leftCount)  / duration,
            right: Double(rightCount) / duration)
        let result = TestResult(
            timestamp: Date(),
            testType: .legAgility,
            part: "both",
            score: Double(leftCount + rightCount) / duration,
            durationMs: Int(duration * 1000),
            errors: 0,
            details: String(format: "left:\(leftCount),right:\(rightCount),asymmetry:%.2f", ai)
        )
        appState.dataManager.writeTestResult(result)
    }
}
