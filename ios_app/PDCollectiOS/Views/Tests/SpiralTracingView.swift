import SwiftUI

struct SpiralTracingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    private enum Phase { case instructions, tracing, done }

    @State private var phase: Phase = .instructions
    @State private var userPath: [CGPoint] = []
    @State private var touchTimestamps: [Date] = []
    @State private var startTime: Date?
    @State private var durationMs = 0
    @State private var features: PDAlgorithms.SpiralFeatures?
    @State private var isPersonalBest = false
    @State private var trendMsg = ""
    @State private var deviationColor: Color = .orange

    var body: some View {
        VStack {
            switch phase {
            case .instructions: instructionsView
            case .tracing:      tracingView
            case .done:         resultView
            }
        }
        .navigationTitle("Spiral Tracing")
        .navigationBarBackButtonHidden(phase == .tracing)
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
                instructionRow(icon: "arrow.up.right", text: "Trace outward along the spiral path")
                instructionRow(icon: "hand.point.up", text: "Stay as close as possible — go steadily")
                instructionRow(icon: "hand.raised", text: "Lift your finger to finish")
            }
            .padding().background(.orange.opacity(0.08)).cornerRadius(14)

            streakBanner

            Button("Start") {
                phase = .tracing
                startTime = Date()
                userPath = []
                touchTimestamps = []
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .tint(.orange)
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
                    if userPath.count > 1 {
                        Path { path in
                            path.move(to: userPath[0])
                            userPath.dropFirst().forEach { path.addLine(to: $0) }
                        }
                        .stroke(deviationColor,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }

                    // Start dot
                    let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                    Circle()
                        .fill(userPath.isEmpty ? Color.green : Color.green.opacity(0.4))
                        .frame(width: 18, height: 18)
                        .position(center)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            userPath.append(value.location)
                            touchTimestamps.append(Date())
                            updateDeviationColor(geo: geo)
                        }
                        .onEnded { _ in
                            let elapsed = Date().timeIntervalSince(startTime ?? Date())
                            durationMs = Int(elapsed * 1000)
                            computeFeatures(geo: geo)
                            phase = .done
                            saveResult(size: geo.size)
                        }
                )
            }

            // Overlay hint
            VStack {
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

                // Spiral quality score (composite)
                if let f = features {
                    spiralScoreGauge(f)
                }

                // Detail card
                VStack(spacing: 8) {
                    resultRow("Duration",        String(format: "%.1f s", Double(durationMs) / 1000))
                    resultRow("Points Recorded", "\(userPath.count)")
                    if let f = features {
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
                }
                .cardStyle()

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
    private func spiralScoreGauge(_ f: PDAlgorithms.SpiralFeatures) -> some View {
        // Composite score 0–100: lower RMSE and tremor = better
        let rmseScore   = max(0, 100 - f.spiralFitRMSE * 2)
        let tremorScore = max(0, 100 - f.tremorRatio * 200)
        let speedScore  = max(0, 100 - f.speedCV * 80)
        let composite   = (rmseScore + tremorScore + speedScore) / 3

        let color: Color = composite > 70 ? .green : (composite > 45 ? .yellow : .orange)

        VStack(spacing: 8) {
            Text("Tracing Quality").font(.headline)
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

    private func updateDeviationColor(geo: GeometryProxy) {
        guard let last = userPath.last else { return }
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

    private func computeFeatures(geo: GeometryProxy) {
        features = PDAlgorithms.spiralFeatures(
            path: userPath, timestamps: touchTimestamps, canvasSize: geo.size)
        if let f = features {
            // Lower RMSE = better (higherIsBetter: false)
            let score = f.spiralFitRMSE
            isPersonalBest = appState.gamification.isPersonalBest(
                testType: "spiral_tracing", score: score, higherIsBetter: false)
            trendMsg = appState.gamification.trendMessage(
                testType: "spiral_tracing", score: score, higherIsBetter: false)
            appState.gamification.recordCompletion(
                testType: "spiral_tracing", score: score, higherIsBetter: false)
        }
    }

    private func saveResult(size: CGSize) {
        let coords = userPath.map { "\(Int($0.x)),\(Int($0.y))" }.joined(separator: "|")
        var details = "points:\(userPath.count),path:\(coords)"
        if let f = features {
            details += String(format: ",rmse:%.2f,tremor:%.4f,speed_cv:%.4f,area:%.0f",
                              f.spiralFitRMSE, f.tremorRatio, f.speedCV, f.boundingArea)
        }
        let result = TestResult(
            timestamp: Date(),
            testType: .spiralTracing,
            part: "trace",
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
