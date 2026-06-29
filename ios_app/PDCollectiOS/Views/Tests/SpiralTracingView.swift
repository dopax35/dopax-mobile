import SwiftUI

struct SpiralTracingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    private enum Phase { case instructions, tracing(hand: Hand), between, done }
    private enum Hand: String { case left = "Left", right = "Right" }

    @State private var phase: Phase = .instructions
    @State private var leftPath: [CGPoint] = []
    @State private var rightPath: [CGPoint] = []
    @State private var leftTimestamps: [Date] = []
    @State private var rightTimestamps: [Date] = []
    @State private var leftDurationMs = 0
    @State private var rightDurationMs = 0
    @State private var leftFeatures: PDAlgorithms.SpiralFeatures?
    @State private var rightFeatures: PDAlgorithms.SpiralFeatures?
    @State private var currentHand: Hand = .left
    @State private var startTime: Date?
    @State private var deviationColor: Color = .orange
    @State private var isPersonalBest = false
    @State private var trendMsg = ""

    private var isTracing: Bool {
        if case .tracing = phase { return true }
        return false
    }

    private var currentPath: [CGPoint] {
        currentHand == .left ? leftPath : rightPath
    }

    var body: some View {
        VStack {
            switch phase {
            case .instructions: instructionsView
            case .tracing:      tracingView
            case .between:      betweenView
            case .done:         resultView
            }
        }
        .navigationTitle("Spiral Tracing")
        .navigationBarBackButtonHidden(isTracing)
    }

    // MARK: - Instructions

    private var instructionsView: some View {
        VStack(spacing: 24) {
            Image(systemName: "tornado")
                .font(.system(size: 64)).foregroundStyle(.orange)
                .modifier(PulseModifier())

            Text("Spiral Tracing Test")
                .font(.title2).fontWeight(.bold)

            VStack(alignment: .leading, spacing: 12) {
                instructionRow(icon: "circle.fill", text: "Start from the GREEN dot in the center")
                instructionRow(icon: "arrow.up.right", text: "Use your LEFT hand to trace outward along the spiral path")
                instructionRow(icon: "hand.point.up", text: "Stay as close as possible — go steadily")
                instructionRow(icon: "hand.raised", text: "Lift your finger to finish")
                instructionRow(icon: "arrow.triangle.2.circlepath", text: "You will repeat for each hand")
            }
            .padding().background(.orange.opacity(0.08)).cornerRadius(14)

            streakBanner

            Button("Start — Left Hand") { startHand(.left) }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .tint(.orange)
        }
        .padding()
    }

    // MARK: - Between Hands

    private var betweenView: some View {
        VStack(spacing: 24) {
            Image(systemName: "hands.clap.fill")
                .font(.system(size: 64)).foregroundStyle(.green)
                .modifier(PulseModifier())

            Text("Left hand done! 🎉")
                .font(.title2).fontWeight(.bold)

            if let f = leftFeatures {
                Text(String(format: "RMSE %.1f  ·  Tremor %.3f", f.spiralFitRMSE, f.tremorRatio))
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

    // MARK: - Tracing Canvas

    private var tracingView: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    // Reference spiral — wide stroke band (guide)
                    SpiralShape(size: geo.size)
                        .stroke(Color.gray.opacity(0.30), lineWidth: 22)

                    // Reference spiral — centre dashed line
                    SpiralShape(size: geo.size)
                        .stroke(Color.gray.opacity(0.65),
                                style: StrokeStyle(lineWidth: 2, dash: [5, 4]))

                    // User's trace — color changes based on deviation
                    if currentPath.count > 1 {
                        Path { path in
                            path.move(to: currentPath[0])
                            currentPath.dropFirst().forEach { path.addLine(to: $0) }
                        }
                        .stroke(deviationColor,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }

                    // Start dot
                    let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                    Circle()
                        .fill(currentPath.isEmpty ? Color.green : Color.green.opacity(0.4))
                        .frame(width: 18, height: 18)
                        .position(center)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            switch currentHand {
                            case .left:
                                leftPath.append(value.location)
                                leftTimestamps.append(Date())
                            case .right:
                                rightPath.append(value.location)
                                rightTimestamps.append(Date())
                            }
                            updateDeviationColor(geo: geo)
                        }
                        .onEnded { _ in
                            finishHand(currentHand, geo: geo)
                        }
                )
            }

            // Overlay hint
            VStack {
                HStack {
                    Text(currentHand.rawValue + " Hand")
                        .font(.headline)
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Spacer()

                HStack(spacing: 8) {
                    Circle().fill(deviationColor).frame(width: 10, height: 10)
                    Text(deviationColor == .green ? "On track!" : (deviationColor == .yellow ? "Getting close to edge…" : "Lift finger to finish"))
                        .font(.caption)
                }
                .padding(10)
                .background(.ultraThinMaterial).cornerRadius(10)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Result

    private var resultView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: isPersonalBest ? "trophy.fill" : "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(isPersonalBest ? .yellow : .orange)
                    .modifier(PulseModifier())

                Text(isPersonalBest ? "New Personal Best! 🏅" : "Test Complete")
                    .font(.title).fontWeight(.bold)
                if !trendMsg.isEmpty {
                    Text(trendMsg).font(.subheadline).foregroundStyle(.secondary)
                }

                // Left hand score
                if let f = leftFeatures {
                    spiralScoreGauge(f, title: "Left Hand – Tracing Quality", color: .blue)
                }

                // Right hand score
                if let f = rightFeatures {
                    spiralScoreGauge(f, title: "Right Hand – Tracing Quality", color: .green)
                }

                // Left detail card
                VStack(spacing: 8) {
                    Text("Left Hand").font(.headline).foregroundStyle(.blue)
                    resultRow("Duration",        String(format: "%.1f s", Double(leftDurationMs) / 1000))
                    resultRow("Points Recorded", "\(leftPath.count)")
                    if let f = leftFeatures {
                        spiralDetailRows(f)
                    }
                }
                .cardStyle()

                // Right detail card
                VStack(spacing: 8) {
                    Text("Right Hand").font(.headline).foregroundStyle(.green)
                    resultRow("Duration",        String(format: "%.1f s", Double(rightDurationMs) / 1000))
                    resultRow("Points Recorded", "\(rightPath.count)")
                    if let f = rightFeatures {
                        spiralDetailRows(f)
                    }
                }
                .cardStyle()

                // Asymmetry card
                asymmetryCard

                Text(appState.gamification.motivationalMessage)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(.orange.opacity(0.08))
                    .cornerRadius(12)

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .tint(.orange)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func spiralDetailRows(_ f: PDAlgorithms.SpiralFeatures) -> some View {
        resultRow("Spiral RMSE",
                  String(format: "%.1f px", f.spiralFitRMSE),
                  note: f.spiralFitRMSE > 30 ? "⚠️ off-path" : nil)
        resultRow("Tremor Ratio",
                  String(format: "%.3f", f.tremorRatio),
                  note: f.tremorRatio > 0.5 ? "⚠️ elevated" : nil)
        resultRow("Speed CoV",
                  String(format: "%.3f", f.speedCV),
                  note: f.speedCV > 0.6 ? "⚠️ variable" : nil)
        resultRow("Curvature CoV",
                  String(format: "%.3f", f.curvatureCV))
        resultRow("Drawing Area",
                  String(format: "%.0f px²", f.boundingArea))
    }

    @ViewBuilder
    private func spiralScoreGauge(_ f: PDAlgorithms.SpiralFeatures,
                                   title: String = "Tracing Quality",
                                   color baseColor: Color = .orange) -> some View {
        // Composite score 0–100: lower RMSE and tremor = better
        let rmseScore   = max(0, 100 - f.spiralFitRMSE * 2)
        let tremorScore = max(0, 100 - f.tremorRatio * 200)
        let speedScore  = max(0, 100 - f.speedCV * 80)
        let composite   = (rmseScore + tremorScore + speedScore) / 3

        let color: Color = composite > 70 ? .green : (composite > 45 ? .yellow : .orange)

        VStack(spacing: 8) {
            Text(title).font(.headline)
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 16)
                    .frame(width: 120, height: 120)
                Circle()
                    .trim(from: 0, to: composite / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: composite)
                Text(String(format: "%.0f", composite))
                    .font(.title.bold())
                    .foregroundStyle(color)
            }
            Text("Based on spiral accuracy, tremor, and speed consistency")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding().cardStyle()
    }

    private var asymmetryCard: some View {
        let leftRMSE  = leftFeatures?.spiralFitRMSE ?? 0
        let rightRMSE = rightFeatures?.spiralFitRMSE ?? 0
        let ai = PDAlgorithms.asymmetryIndex(left: leftRMSE, right: rightRMSE)
        let color: Color = ai < 10 ? .green : (ai < 20 ? .yellow : .orange)

        return VStack(spacing: 8) {
            HStack {
                Text("Side Asymmetry (RMSE)").font(.headline)
                Spacer()
                Text(String(format: "%.1f%%", ai))
                    .font(.title3.bold())
                    .foregroundStyle(color)
            }
            HStack {
                Text(String(format: "L %.1f", leftRMSE))
                    .font(.caption).foregroundStyle(.blue)
                Spacer()
                Text(String(format: "R %.1f", rightRMSE))
                    .font(.caption).foregroundStyle(.green)
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
            Image(systemName: icon).foregroundStyle(.orange)
            Text(text).font(.callout)
        }
    }

    // MARK: - Logic

    private func startHand(_ hand: Hand) {
        currentHand = hand
        deviationColor = .orange
        startTime = Date()

        switch hand {
        case .left:
            leftPath = []
            leftTimestamps = []
        case .right:
            rightPath = []
            rightTimestamps = []
        }

        phase = .tracing(hand: hand)
    }

    private func finishHand(_ hand: Hand, geo: GeometryProxy) {
        let elapsed = Date().timeIntervalSince(startTime ?? Date())

        switch hand {
        case .left:
            leftDurationMs = Int(elapsed * 1000)
            leftFeatures = PDAlgorithms.spiralFeatures(
                path: leftPath, timestamps: leftTimestamps, canvasSize: geo.size)
            saveResult(hand: .left, size: geo.size)
            phase = .between

        case .right:
            rightDurationMs = Int(elapsed * 1000)
            rightFeatures = PDAlgorithms.spiralFeatures(
                path: rightPath, timestamps: rightTimestamps, canvasSize: geo.size)
            saveResult(hand: .right, size: geo.size)
            computeTrend()
            phase = .done
        }
    }

    private func computeTrend() {
        // Use average RMSE across both hands (lower = better)
        let avgRMSE = ((leftFeatures?.spiralFitRMSE ?? 0) + (rightFeatures?.spiralFitRMSE ?? 0)) / 2
        isPersonalBest = appState.gamification.isPersonalBest(
            testType: "spiral_tracing", score: avgRMSE, higherIsBetter: false)
        trendMsg = appState.gamification.trendMessage(
            testType: "spiral_tracing", score: avgRMSE, higherIsBetter: false)
        appState.gamification.recordCompletion(
            testType: "spiral_tracing", score: avgRMSE, higherIsBetter: false)
    }

    private func updateDeviationColor(geo: GeometryProxy) {
        guard let last = currentPath.last else { return }
        let distToSpiral = distanceToIdealSpiral(point: last, size: geo.size)
        deviationColor = distToSpiral < 18 ? .green : (distToSpiral < 36 ? .yellow : .orange)
    }

    /// Approximate distance from a point to the nearest point on the ideal spiral
    private func distanceToIdealSpiral(point: CGPoint, size: CGSize) -> Double {
        let turns: Double = 3
        let pointCount = 300
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxR = Double(min(size.width, size.height)) * 0.44
        var minDist = Double.infinity
        for i in 0...pointCount {
            let theta = Double(i) / Double(pointCount) * turns * 2 * .pi
            let r = (theta / (turns * 2 * .pi)) * maxR
            let sx = Double(center.x) + r * cos(theta)
            let sy = Double(center.y) + r * sin(theta)
            let d = sqrt((Double(point.x) - sx) * (Double(point.x) - sx) +
                         (Double(point.y) - sy) * (Double(point.y) - sy))
            if d < minDist { minDist = d }
        }
        return minDist
    }

    private func saveResult(hand: Hand, size: CGSize) {
        let path = hand == .left ? leftPath : rightPath
        let features = hand == .left ? leftFeatures : rightFeatures
        let durationMs = hand == .left ? leftDurationMs : rightDurationMs

        let coords = path.map { "\(Int($0.x)),\(Int($0.y))" }.joined(separator: "|")
        var details = "points:\(path.count),path:\(coords)"
        if let f = features {
            details += String(format: ",rmse:%.2f,tremor:%.4f,speed_cv:%.4f,area:%.0f",
                              f.spiralFitRMSE, f.tremorRatio, f.speedCV, f.boundingArea)
        }
        let result = TestResult(
            timestamp: Date(),
            testType: .spiralTracing,
            part: hand.rawValue,
            score: features?.spiralFitRMSE ?? Double(durationMs) / 1000.0,
            durationMs: durationMs,
            errors: 0,
            details: details
        )
        appState.dataManager.writeTestResult(result)
    }
}

// MARK: - Archimedean Spiral Shape

private struct SpiralShape: Shape {
    let size: CGSize
    var turns: Double = 3
    var pointCount = 600

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maxR = min(rect.width, rect.height) * 0.44
        var path = Path()
        for i in 0...pointCount {
            let theta = Double(i) / Double(pointCount) * turns * 2 * .pi
            let r = CGFloat(theta / (turns * 2 * .pi)) * maxR
            let x = center.x + r * CGFloat(cos(theta))
            let y = center.y + r * CGFloat(sin(theta))
            let pt = CGPoint(x: x, y: y)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        return path
    }
}
