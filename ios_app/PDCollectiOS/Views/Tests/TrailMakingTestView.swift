import SwiftUI

struct TrailMakingTestView: View {
    enum Part { case A, B }
    let part: Part

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var phase: Phase = .instructions
    @State private var targets: [TMTTarget] = []
    @State private var nextIndex = 0
    @State private var lines: [(from: CGPoint, to: CGPoint, time: Double)] = []
    @State private var errors = 0
    @State private var startTime: Date?
    @State private var segmentStart: Date?
    @State private var segmentTimes: [Double] = []
    @State private var totalMs = 0
    @State private var isPersonalBest = false
    @State private var trendMsg = ""
    @State private var baRatio: Double? = nil

    // Drag state
    @State private var dragPoint: CGPoint? = nil          // live finger position
    @State private var errorFlash = false                 // brief red flash on lift-off miss

    private enum Phase { case instructions, running, done }

    private var testTypeKey: String {
        part == .A ? "trail_making_A" : "trail_making_B"
    }

    private var sequence: [String] {
        part == .A
            ? (1...10).map(String.init)
            : zip(1...5, ["A","B","C","D","E"]).flatMap { [String($0), $1] }
    }

    var body: some View {
        Group {
            switch phase {
            case .instructions: instructionsView
            case .running:      testCanvas
            case .done:         resultView
            }
        }
        .navigationTitle("TMT \(part == .A ? "A" : "B")")
        .navigationBarBackButtonHidden(phase == .running)
    }

    // MARK: - Instructions

    private var instructionsView: some View {
        VStack(spacing: 24) {
            Image(systemName: part == .A ? "number.circle" : "character.cursor.ibeam")
                .font(.system(size: 64))
                .foregroundStyle(part == .A ? Color.purple : Color.indigo)

            Text("Trail Making — Part \(part == .A ? "A" : "B")")
                .font(.title2).fontWeight(.bold)

            VStack(alignment: .leading, spacing: 12) {
                if part == .A {
                    instructionRow(icon: "1.circle.fill",
                                   text: "Connect circles 1 → 2 → 3 … → 10 in order")
                    instructionRow(icon: "hand.draw", text: "Keep your finger on the screen the whole time")
                    instructionRow(icon: "arrow.uturn.backward", text: "If you lift your finger, you go back to the last point")
                } else {
                    instructionRow(icon: "arrow.left.arrow.right",
                                   text: "Alternate: 1 → A → 2 → B → 3 → C … → 5 → E")
                    instructionRow(icon: "hand.draw",
                                   text: "Keep your finger on the screen the whole time")
                    instructionRow(icon: "chart.bar.fill",
                                   text: "Your B:A ratio will be compared to Part A time")
                }
            }
            .padding().background(accentColor.opacity(0.08)).cornerRadius(14)

            streakBanner

            Button("Start Test") {
                phase = .running
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(accentColor)
        }
        .padding()
    }

    // MARK: - Canvas

    private var testCanvas: some View {
        GeometryReader { geo in
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                // Error flash overlay
                if errorFlash {
                    Color.red.opacity(0.18)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }

                // Completed path lines — colour-coded by segment speed
                Canvas { ctx, _ in
                    for line in lines {
                        var path = Path()
                        path.move(to: line.from)
                        path.addLine(to: line.to)
                        let avgMs = segmentTimes.isEmpty ? line.time
                            : segmentTimes.reduce(0,+) / Double(segmentTimes.count)
                        let fastness = min(max(avgMs / line.time, 0.3), 3.0)
                        let col: Color = fastness > 1.5 ? .green : (fastness > 0.8 ? .blue : .orange)
                        ctx.stroke(path, with: .color(col.opacity(0.8)), lineWidth: 3)
                    }

                    // Live rubber-band line from last completed point to finger
                    if let fp = dragPoint, nextIndex > 0 {
                        let from = targets[nextIndex - 1].position
                        var path = Path()
                        path.move(to: from)
                        path.addLine(to: fp)
                        ctx.stroke(path, with: .color(accentColor.opacity(0.5)),
                                   style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    }
                }
                .animation(nil, value: lines.count)
                .animation(nil, value: dragPoint == nil)

                // Targets — plain circles, no highlighting
                ForEach(targets.indices, id: \.self) { i in
                    let t = targets[i]
                    let isDone = i < nextIndex

                    ZStack {
                        Circle()
                            .fill(isDone ? accentColor.opacity(0.6) : Color(.systemGray5))
                        Circle()
                            .stroke(isDone ? accentColor : Color.secondary.opacity(0.4), lineWidth: 2)
                        Text(t.label)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(isDone ? .white : .primary)
                    }
                    .frame(width: Constants.TMT.targetRadius * 2,
                           height: Constants.TMT.targetRadius * 2)
                    .position(t.position)
                }

                // Invisible full-canvas drag recogniser
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                let loc = value.location
                                dragPoint = loc
                                checkProgress(at: loc)
                            }
                            .onEnded { _ in
                                // Finger lifted — cancel rubber band
                                dragPoint = nil
                                // Flash to signal lift-off
                                if nextIndex > 0 && nextIndex < targets.count {
                                    triggerErrorFlash()
                                }
                            }
                    )

                // HUD
                VStack {
                    HStack {
                        Label("\(nextIndex)/\(targets.count)", systemImage: "checkmark")
                            .font(.headline)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.ultraThinMaterial).cornerRadius(10)

                        Spacer()

                        ElapsedTimerView(start: startTime)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.ultraThinMaterial).cornerRadius(10)

                        Spacer()

                        Label("\(errors)", systemImage: "xmark")
                            .font(.headline)
                            .foregroundStyle(errors > 0 ? .orange : .primary)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.ultraThinMaterial).cornerRadius(10)
                    }
                    .padding()
                    Spacer()
                }
            }
        }
        .onAppear { layoutTargets() }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Result

    private var resultView: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: isPersonalBest ? "trophy.fill" : (errors == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill"))
                        .font(.system(size: 64))
                        .foregroundStyle(isPersonalBest ? .yellow : (errors == 0 ? accentColor : .orange))

                    Text(isPersonalBest ? "New Personal Best! 🏅" : "Test Complete")
                        .font(.title).fontWeight(.bold)
                    if !trendMsg.isEmpty {
                        Text(trendMsg).font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 8) {
                    resultRow("Part", "TMT-\(part == .A ? "A" : "B")")
                    resultRow("Total Time", String(format: "%.2f s", Double(totalMs) / 1000))
                    resultRow("Lift-offs", "\(errors)", note: errors > 2 ? "⚠️" : nil)
                    if !segmentTimes.isEmpty {
                        let avg = segmentTimes.reduce(0,+) / Double(segmentTimes.count)
                        resultRow("Avg Segment", String(format: "%.1f ms", avg))
                        let cv = PDAlgorithms.stddev(segmentTimes.map { $0 }) / (avg + 1e-12)
                        resultRow("Segment CoV", String(format: "%.3f", cv),
                                  note: cv > 0.4 ? "⚠️ variable" : nil)
                        let sorted = segmentTimes.sorted(by: >)
                        if let slowest = sorted.first, slowest > avg * 2.0 {
                            resultRow("Slowest Segment",
                                      String(format: "%.1f ms", slowest),
                                      note: "⚠️ freezing?")
                        }
                    }
                }
                .cardStyle()

                if part == .B, let ba = baRatio {
                    baRatioCard(ba)
                }

                if segmentTimes.count > 2 {
                    segmentSparkline
                }

                Text(appState.gamification.motivationalMessage)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(accentColor.opacity(0.08))
                    .cornerRadius(12)

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(accentColor)
            }
            .padding()
        }
    }

    // MARK: - B:A Ratio Card

    @ViewBuilder
    private func baRatioCard(_ ratio: Double) -> some View {
        let color: Color = ratio < 2.0 ? .green : (ratio < 3.0 ? .yellow : .orange)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("B:A Ratio").font(.headline)
                    Text("Cognitive load index").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.2f×", ratio))
                        .font(.title2.bold()).foregroundStyle(color)
                    Text(ratio < 2 ? "Normal" : (ratio < 3 ? "Elevated" : "⚠️ High"))
                        .font(.caption).foregroundStyle(color)
                }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 8)
                    Capsule().fill(color)
                        .frame(width: g.size.width * min((ratio - 1.0) / 4.0, 1.0), height: 8)
                        .animation(.easeOut(duration: 0.8), value: ratio)
                }
            }
            .frame(height: 8)
            Text("< 2× normal · 2–3× mild · > 3× may indicate executive function impairment")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding().cardStyle()
    }

    // MARK: - Segment Sparkline

    @ViewBuilder
    private var segmentSparkline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Segment Speed Timeline")
                .font(.headline)
            HStack(alignment: .bottom, spacing: 3) {
                let maxT = segmentTimes.max() ?? 1
                ForEach(segmentTimes.indices, id: \.self) { i in
                    let t = segmentTimes[i]
                    let frac = CGFloat(t / maxT)
                    let avg = segmentTimes.reduce(0,+) / Double(segmentTimes.count)
                    let col: Color = t > avg * 1.5 ? .orange : .blue
                    RoundedRectangle(cornerRadius: 3)
                        .fill(col)
                        .frame(maxWidth: .infinity, minHeight: 4,
                               maxHeight: max(4, 80 * frac))
                }
            }
            .frame(height: 80)
            Text("Each bar = one segment. Tall = slow. Orange = significantly above average.")
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
            Image(systemName: icon).foregroundStyle(accentColor)
            Text(text).font(.callout)
        }
    }

    private var accentColor: Color { part == .A ? .purple : .indigo }

    // MARK: - Logic

    private func layoutTargets() {
        let screenBounds = UIScreen.main.bounds
        let w = screenBounds.width
        let h = screenBounds.height - 160
        let r = Constants.TMT.targetRadius
        let pad: CGFloat = r + 16
        let minDist = Constants.TMT.minSpacing

        var positions: [CGPoint] = []
        var attempts = 0
        while positions.count < sequence.count && attempts < 2000 {
            let x = CGFloat.random(in: pad...(w - pad))
            let y = CGFloat.random(in: pad...(h - pad))
            let p = CGPoint(x: x, y: y)
            let tooClose = positions.contains { hypot($0.x - p.x, $0.y - p.y) < minDist }
            if !tooClose { positions.append(p) }
            attempts += 1
        }
        targets = zip(sequence, positions).map { TMTTarget(label: $0, position: $1) }
        startTime = Date()
        segmentStart = Date()
    }

    /// Called on every drag update — checks if the finger is over the next target.
    private func checkProgress(at loc: CGPoint) {
        guard phase == .running, nextIndex < targets.count else { return }
        let target = targets[nextIndex]
        let dist = hypot(loc.x - target.position.x, loc.y - target.position.y)

        if dist <= Constants.TMT.targetRadius {
            // Finger reached the next target!
            let now = Date()
            if let segStart = segmentStart {
                let elapsed = now.timeIntervalSince(segStart) * 1000
                segmentTimes.append(elapsed)
            }
            segmentStart = now

            if nextIndex > 0 {
                let timeMs = segmentTimes.last ?? 0
                lines.append((from: targets[nextIndex - 1].position,
                               to: target.position,
                               time: timeMs))
            }
            nextIndex += 1

            if nextIndex == targets.count {
                let total = Date().timeIntervalSince(startTime ?? Date()) * 1000
                totalMs = Int(total)
                dragPoint = nil
                phase = .done
                computeResults()
                saveResult()
            }
        }
    }

    private func triggerErrorFlash() {
        errors += 1
        withAnimation(.easeOut(duration: 0.1)) { errorFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation { errorFlash = false }
        }
    }

    private func computeResults() {
        let scoreS = Double(totalMs) / 1000.0
        isPersonalBest = appState.gamification.isPersonalBest(
            testType: testTypeKey, score: scoreS, higherIsBetter: false)
        trendMsg = appState.gamification.trendMessage(
            testType: testTypeKey, score: scoreS, higherIsBetter: false)
        appState.gamification.recordCompletion(
            testType: testTypeKey, score: scoreS, higherIsBetter: false)

        if part == .B {
            if let aTime = appState.gamification.personalBest(testType: "trail_making_A"),
               aTime > 0 {
                baRatio = scoreS / aTime
            }
        }
    }

    private func saveResult() {
        let segStr = segmentTimes.map { String(format: "%.0f", $0) }.joined(separator: "|")
        var details = "segments:\(segStr)"
        if let ba = baRatio { details += String(format: ",ba_ratio:%.3f", ba) }
        let result = TestResult(
            timestamp: Date(),
            testType: .trailMaking,
            part: part == .A ? "A" : "B",
            score: Double(totalMs) / 1000.0,
            durationMs: totalMs,
            errors: errors,
            details: details
        )
        appState.dataManager.writeTestResult(result)
    }
}

// MARK: - Elapsed Timer

private struct ElapsedTimerView: View {
    let start: Date?
    @State private var elapsed: Double = 0
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(String(format: "%.1f s", elapsed))
            .font(.headline.monospacedDigit())
            .onReceive(timer) { _ in
                elapsed = Date().timeIntervalSince(start ?? Date())
            }
    }
}

// MARK: - Model

private struct TMTTarget {
    let label: String
    var position: CGPoint
}
