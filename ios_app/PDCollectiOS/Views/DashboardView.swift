import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var metrics: [GaitMetric] = []
    @State private var asymmetryPoints: [AsymmetryPoint] = []
    @State private var isLoading = false
    @State private var selectedTab = 0
    @State private var showHealthKitError = false

    private var summary: GaitSummary { GaitSummary(metrics: metrics) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Collection status banner (new — iPhone branch)
                    collectionStatusSection

                    if isLoading {
                        ProgressView("Loading HealthKit data…")
                            .padding(.top, 40)
                    } else if metrics.isEmpty && asymmetryPoints.isEmpty {
                        healthKitEmptyState
                    } else {
                        if !metrics.isEmpty { statsRow }
                        chartSection
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: loadData) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .alert("HealthKit Unavailable", isPresented: $showHealthKitError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(appState.healthKitManager.authorizationError ?? "Could not access HealthKit.")
            }
        }
        .onAppear { Task { await requestAndLoad() } }
    }

    // MARK: - Collection Status Section (new)

    private var collectionStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Active Services")
                .font(.headline)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ServiceStatusCard(
                        title: "Sensors",
                        icon: "gyroscope",
                        color: appState.passiveSensor.isRunning ? .green : .gray,
                        detail: appState.passiveSensor.isRunning
                            ? "\(appState.passiveSensor.totalReadingsToday) readings today"
                            : "Stopped"
                    )
                    ServiceStatusCard(
                        title: "Face Cam",
                        icon: "camera.fill",
                        color: appState.faceDistance.isRunning ? .green : .gray,
                        detail: appState.faceDistance.isRunning
                            ? "\(appState.faceDistance.samplesCollected) samples"
                            : "Stopped"
                    )
                    ServiceStatusCard(
                        title: "Touch Log",
                        icon: "hand.point.up",
                        color: appState.appEventLogger.isRunning ? .green : .gray,
                        detail: appState.appEventLogger.isRunning ? "Active" : "Stopped"
                    )
                    ServiceStatusCard(
                        title: "BG Tasks",
                        icon: "clock.arrow.2.circlepath",
                        color: .blue,
                        detail: "Scheduled"
                    )
                }
                .padding(.horizontal)
            }

            if !appState.isCollecting {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Collection is paused. Enable it in Settings.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Subviews (existing)

    private var statsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                StatCard(
                    title: "Walking Speed",
                    value: summary.averageWalkingSpeed.map { String(format: "%.2f m/s", $0) } ?? "–",
                    icon: "figure.walk",
                    subtitle: "30-day avg"
                )
                StatCard(
                    title: "Step Length",
                    value: summary.averageStepLength.map { String(format: "%.2f m", $0) } ?? "–",
                    icon: "ruler",
                    subtitle: "30-day avg"
                )
                StatCard(
                    title: "Steadiness",
                    value: summary.latestSteadiness.map { String(format: "%.0f%%", $0 * 100) } ?? "–",
                    icon: "waveform.path.ecg",
                    subtitle: "Latest"
                )
                StatCard(
                    title: "Heart Rate",
                    value: summary.averageHeartRate.map { String(format: "%.0f bpm", $0) } ?? "–",
                    icon: "heart.fill",
                    subtitle: "30-day avg"
                )
            }
            .padding(.horizontal)
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(["Speed","Step Len","Steadiness","HR","Asymmetry"].enumerated()), id: \.offset) { i, label in
                        Button(action: { withAnimation { selectedTab = i } }) {
                            Text(label)
                                .font(.caption.weight(selectedTab == i ? .bold : .regular))
                                .padding(.vertical, 6).padding(.horizontal, 12)
                                .background(selectedTab == i ? Color.accentColor : Color.clear)
                                .foregroundStyle(selectedTab == i ? .white : .primary)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(4)
                .background(Color(.systemGray6))
                .cornerRadius(10)
            }
            .padding(.horizontal)

            if selectedTab == 4 {
                // Asymmetry chart
                asymmetryChartView
            } else {
                let points = chartPoints
                if points.isEmpty {
                    EmptyStateView(title: "No data for this metric", systemImage: "chart.xyaxis.line")
                        .frame(height: 220)
                } else {
                    Chart(points) { p in
                        LineMark(
                            x: .value("Date", p.date, unit: .day),
                            y: .value(metricLabel, p.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.blue)
                        PointMark(
                            x: .value("Date", p.date, unit: .day),
                            y: .value(metricLabel, p.value)
                        )
                        .foregroundStyle(.blue)
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.month().day()) } }
                    .frame(height: 220)
                    .padding(.horizontal)
                }
                Text(metricDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
        }
    }

    private var healthKitEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 56))
                .foregroundColor(.blue)
            Text("HealthKit Data")
                .font(.title2).fontWeight(.semibold)
            Text("Walk with your iPhone in your pocket for a few days and iOS will automatically compute gait metrics that appear here.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 32)
            Button("Grant HealthKit Access") {
                Task { await requestAndLoad() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 40)
    }

    // MARK: - Asymmetry Chart

    private struct AsymmetryPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double   // asymmetry index 0–100
        let series: String  // "Finger Tapping" or "Leg Agility"
    }

    private var asymmetryChartView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if asymmetryPoints.isEmpty {
                EmptyStateView(
                    title: "No asymmetry data yet",
                    systemImage: "arrow.left.arrow.right",
                    descriptionText: "Complete Finger Tapping or Leg Agility tests to see bilateral asymmetry trends."
                )
                .frame(height: 220)
            } else {
                Chart(asymmetryPoints) { p in
                    LineMark(
                        x: .value("Date", p.date, unit: .day),
                        y: .value("Asymmetry %", p.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(by: .value("Test", p.series))

                    PointMark(
                        x: .value("Date", p.date, unit: .day),
                        y: .value("Asymmetry %", p.value)
                    )
                    .foregroundStyle(by: .value("Test", p.series))

                    // 10% reference line (symmetric threshold)
                    RuleMark(y: .value("Symmetric", 10.0))
                        .foregroundStyle(Color.green.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .trailing) {
                            Text("10%").font(.caption2).foregroundStyle(.green)
                        }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisGridLine(); AxisTick()
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .chartYAxis {
                    AxisMarks { v in
                        AxisGridLine()
                        AxisValueLabel { Text("\(v.as(Double.self).map { Int($0) } ?? 0)%") }
                    }
                }
                .frame(height: 220)
                .padding(.horizontal)
                .chartForegroundStyleScale([
                    "Finger Tapping": Color.blue,
                    "Leg Agility":    Color.red
                ])
            }

            Text("Asymmetry Index = |Left − Right| / avg × 100%. < 10% symmetric · 10–20% mild · > 20% clinically notable.")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
        }
    }

    /// Parse test_results.csv and extract bilateral asymmetry data points.
    private func loadAsymmetryData() {
        let fm = FileManager.default
        let docsDir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let rootDir = docsDir
            .appendingPathComponent("PDCollect")
            .appendingPathComponent(appState.userProfile.userId)

        guard let dateDirs = try? fm.contentsOfDirectory(
            at: rootDir, includingPropertiesForKeys: [.isDirectoryKey]) else { return }

        var points: [AsymmetryPoint] = []

        // Try both ISO8601 formats
        let isoFmtFull = ISO8601DateFormatter()
        isoFmtFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFmtBasic = ISO8601DateFormatter()

        func parseDate(_ s: String) -> Date? {
            isoFmtFull.date(from: s) ?? isoFmtBasic.date(from: s)
        }

        for dateDir in dateDirs {
            let csvURL = dateDir.appendingPathComponent(Constants.CSV.testResultsFile)
            guard let content = try? String(contentsOf: csvURL, encoding: .utf8) else { continue }

            var ftLeft:  (date: Date, rate: Double)? = nil
            var ftRight: (date: Date, rate: Double)? = nil
            var laLeft:  (date: Date, rate: Double)? = nil
            var laRight: (date: Date, rate: Double)? = nil

            for rawLine in content.components(separatedBy: "\n").dropFirst() {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { continue }

                // Quote-aware CSV split (max 7 columns; quoted details may contain commas)
                let cols = csvSplit(line, maxCols: 7)
                guard cols.count >= 4,
                      let date  = parseDate(cols[0]),
                      let score = Double(cols[3]) else { continue }

                let type    = cols[1]
                let part    = cols[2]
                let details = cols.count >= 7
                    ? cols[6].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    : ""

                switch type {
                case "finger_tapping":
                    if part == "Left"  { ftLeft  = (date, score) }
                    if part == "Right" { ftRight = (date, score) }

                case "leg_agility":
                    if let l = csvKeyDouble(details, "left"),
                       let r = csvKeyDouble(details, "right"), (l + r) > 0 {
                        laLeft  = (date, l / 10.0)
                        laRight = (date, r / 10.0)
                    }

                default: break
                }
            }

            if let l = ftLeft, let r = ftRight {
                let ai = PDAlgorithms.asymmetryIndex(left: l.rate, right: r.rate)
                points.append(AsymmetryPoint(date: l.date, value: ai, series: "Finger Tapping"))
            }
            if let l = laLeft, let r = laRight {
                let ai = PDAlgorithms.asymmetryIndex(left: l.rate, right: r.rate)
                points.append(AsymmetryPoint(date: l.date, value: ai, series: "Leg Agility"))
            }
        }

        asymmetryPoints = points.sorted { $0.date < $1.date }
    }

    /// Quote-aware CSV split.
    private func csvSplit(_ line: String, maxCols: Int) -> [String] {
        var cols: [String] = []; var cur = ""; var inQ = false
        for ch in line {
            if ch == "\"" { inQ.toggle() }
            else if ch == "," && !inQ && cols.count < maxCols - 1 { cols.append(cur); cur = "" }
            else { cur.append(ch) }
        }
        cols.append(cur); return cols
    }

    /// Extract numeric value for key from "key:value,..." string.
    private func csvKeyDouble(_ text: String, _ key: String) -> Double? {
        guard let r = text.range(of: "\(key):([-\\d.]+)", options: .regularExpression) else { return nil }
        return Double(String(text[r]).replacingOccurrences(of: "\(key):", with: ""))
    }


    // MARK: - Helpers

    private struct ChartPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    private var chartPoints: [ChartPoint] {
        metrics.compactMap { m -> ChartPoint? in
            let val: Double?
            switch selectedTab {
            case 0: val = m.walkingSpeed
            case 1: val = m.stepLength
            case 2: val = m.walkingSteadiness.map { $0 * 100 }
            case 3: val = m.heartRate
            default: val = nil
            }
            return val.map { ChartPoint(date: m.date, value: $0) }
        }
    }

    private var metricLabel: String {
        ["Walking Speed (m/s)", "Step Length (m)", "Steadiness (%)", "Heart Rate (bpm)"][selectedTab]
    }

    private var metricDescription: String {
        [
            "Walking speed measured by your iPhone's sensors during daily walking. Lower values may indicate gait changes.",
            "Average step length during daily walking. Shorter steps can be an early PD marker.",
            "Apple's walking steadiness score (0–100%). Values below 40% indicate high fall risk.",
            "Average resting heart rate from HealthKit."
        ][selectedTab]
    }

    private func requestAndLoad() async {
        isLoading = true
        loadAsymmetryData()
        if !appState.healthKitManager.isAuthorized {
            await appState.healthKitManager.requestAuthorization()
        }
        if let err = appState.healthKitManager.authorizationError {
            isLoading = false
            if !err.isEmpty { showHealthKitError = true }
            return
        }
        metrics = await appState.healthKitManager.fetchGaitMetrics(days: 30)
        isLoading = false
    }

    private func loadData() {
        Task { await requestAndLoad() }
    }
}

// MARK: - Service Status Card

private struct ServiceStatusCard: View {
    let title: String
    let icon: String
    let color: Color
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                Spacer()
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
            Text(detail)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(width: 110)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(10)
    }
}
