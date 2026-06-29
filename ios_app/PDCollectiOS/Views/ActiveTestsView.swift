import SwiftUI

struct ActiveTestsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Streak / compliance header
                    streakHeader

                    // Due today banner
                    dueTodaySection

                    // Test groups
                    testGroup(title: "🧠 Cognitive", color: .purple, tests: [
                        TestConfig(
                            title: "Trail Making A",
                            subtitle: "Connect numbers 1–10 in order",
                            icon: "number.circle",
                            color: .purple,
                            testType: "trail_making_A",
                            destination: AnyView(TrailMakingTestView(part: .A))
                        ),
                        TestConfig(
                            title: "Trail Making B",
                            subtitle: "Alternate numbers and letters",
                            icon: "character.cursor.ibeam",
                            color: .indigo,
                            testType: "trail_making_B",
                            destination: AnyView(TrailMakingTestView(part: .B))
                        ),
                    ])

                    testGroup(title: "💪 Motor", color: .blue, tests: [
                        TestConfig(
                            title: "Finger Tapping",
                            subtitle: "Alternate taps · 10 s per hand",
                            icon: "hand.point.up",
                            color: .blue,
                            testType: "finger_tapping",
                            destination: AnyView(FingerTappingView())
                        ),
                        TestConfig(
                            title: "Hand Turning",
                            subtitle: "Pronation/supination · 10 s",
                            icon: "arrow.clockwise",
                            color: .green,
                            testType: "hand_turning",
                            destination: AnyView(HandTurningView())
                        ),
                        TestConfig(
                            title: "Spiral Tracing",
                            subtitle: "Trace the spiral accurately",
                            icon: "tornado",
                            color: .orange,
                            testType: "spiral_tracing",
                            destination: AnyView(SpiralTracingView())
                        ),
                        TestConfig(
                            title: "Leg Agility",
                            subtitle: "Alternate heel taps · 10 s",
                            icon: "figure.walk.motion",
                            color: .red,
                            testType: "leg_agility",
                            destination: AnyView(LegAgilityView())
                        ),
                    ])
                }
                .padding(.vertical)
            }
            .navigationTitle("Active Tests")
            .onAppear { appState.gamification.refresh() }
        }
    }

    // MARK: - Streak Header

    private var streakHeader: some View {
        HStack(spacing: 16) {
            // Big streak emoji + count
            VStack(spacing: 2) {
                Text(appState.gamification.streakEmoji)
                    .font(.system(size: 36))
                Text("\(appState.gamification.currentStreak)")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                Text("day streak")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 90)
            .padding()
            .background(.orange.opacity(0.1))
            .cornerRadius(16)

            VStack(alignment: .leading, spacing: 6) {
                Text(appState.gamification.motivationalMessage)
                    .font(.callout).fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)

                // Completion rings for today
                HStack(spacing: 8) {
                    let types = ["finger_tapping", "hand_turning",
                                 "spiral_tracing", "leg_agility",
                                 "trail_making_A", "trail_making_B"]
                    let done = types.filter { appState.gamification.isCompletedToday(testType: $0) }.count
                    Text("\(done)/\(types.count) today")
                        .font(.caption).foregroundStyle(.secondary)

                    MiniProgressBar(value: Double(done) / Double(types.count))
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(18)
        .padding(.horizontal)
    }

    // MARK: - Due Today

    @ViewBuilder
    private var dueTodaySection: some View {
        let overdue = [
            ("finger_tapping", "Finger Tapping"),
            ("hand_turning", "Hand Turning"),
            ("spiral_tracing", "Spiral Tracing"),
            ("leg_agility", "Leg Agility"),
            ("trail_making_A", "Trail Making A"),
            ("trail_making_B", "Trail Making B"),
        ].filter { !appState.gamification.isCompletedToday(testType: $0.0) }

        if !overdue.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Due Today")
                    .font(.headline).padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(overdue, id: \.0) { (type, name) in
                            DueTodayChip(name: name,
                                         daysSince: appState.gamification.daysSinceLastCompleted(testType: type))
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - Test Group

    @ViewBuilder
    private func testGroup(title: String, color: Color,
                           tests: [TestConfig]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).padding(.horizontal)

            VStack(spacing: 0) {
                ForEach(Array(tests.enumerated()), id: \.offset) { idx, config in
                    if idx > 0 { Divider().padding(.leading, 76) }
                    TestRow(config: config)
                }
            }
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
            .padding(.horizontal)
        }
    }
}

// MARK: - TestConfig

private struct TestConfig {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let testType: String
    let destination: AnyView
}

// MARK: - TestRow

private struct TestRow: View {
    @EnvironmentObject var appState: AppState
    let config: TestConfig

    var body: some View {
        NavigationLink(destination: config.destination.environmentObject(appState)) {
            HStack(spacing: 14) {
                // Icon with completion ring overlay
                ZStack {
                    // Completion ring
                    let done = appState.gamification.isCompletedToday(testType: config.testType)
                    let days = appState.gamification.daysSinceLastCompleted(testType: config.testType)
                    Circle()
                        .stroke(ringColor(done: done, days: days),
                                style: StrokeStyle(lineWidth: 3, dash: done ? [] : [3, 2]))
                        .frame(width: 50, height: 50)

                    Image(systemName: config.icon)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(config.color)
                        .cornerRadius(10)

                    if done {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.green)
                            .background(Color.white.clipShape(Circle()))
                            .offset(x: 18, y: -18)
                    }
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text(config.title).fontWeight(.medium)
                    Text(config.subtitle).font(.caption).foregroundStyle(.secondary)
                }

                Spacer()

                // Last-done indicator
                if let days = appState.gamification.daysSinceLastCompleted(testType: config.testType) {
                    Text(days == 0 ? "Today" : "\(days)d ago")
                        .font(.caption2)
                        .foregroundStyle(days == 0 ? .green : (days == 1 ? .yellow : .orange))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background((days == 0 ? Color.green : (days == 1 ? Color.yellow : Color.orange)).opacity(0.15))
                        .cornerRadius(8)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal)
        }
    }

    private func ringColor(done: Bool, days: Int?) -> Color {
        if done { return .green }
        guard let d = days else { return .gray.opacity(0.3) }
        return d <= 1 ? .yellow : .orange
    }
}

// MARK: - Helper Views

private struct MiniProgressBar: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemGray5)).frame(height: 6)
                Capsule().fill(Color.green)
                    .frame(width: g.size.width * value, height: 6)
                    .animation(.easeOut, value: value)
            }
        }
        .frame(height: 6)
    }
}

private struct DueTodayChip: View {
    let name: String
    let daysSince: Int?

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(chipColor)
            Text(name).font(.caption2).fontWeight(.medium)
            if let d = daysSince {
                Text(d == 0 ? "Do it now!" : "\(d)d overdue")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Never done").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 80)
        .padding(8)
        .background(chipColor.opacity(0.1))
        .cornerRadius(12)
    }

    private var chipColor: Color {
        guard let d = daysSince else { return .gray }
        return d == 0 ? .orange : (d <= 1 ? .yellow : .red)
    }
}
