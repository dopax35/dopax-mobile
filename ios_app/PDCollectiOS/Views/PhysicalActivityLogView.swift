import SwiftUI

/// Physical activity logging view — lets the user report an activity type and time.
/// Ported from the Android dialog-based flow into a native SwiftUI Form.
struct PhysicalActivityLogView: View {
    @EnvironmentObject var appState: AppState

    // MARK: - State

    @State private var selectedActivity = PhysicalActivityEvent.activityTypes[0]
    @State private var selectedTime = Date()
    /// Today's logged events (local, in-memory for the current session).
    @State private var recentLogs: [PhysicalActivityEvent] = []
    /// Drives the success state animation.
    @State private var showSuccess = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                logActivitySection
                recentLogsSection
            }
            .navigationTitle("Activity Log")
        }
    }

    // MARK: - Log Activity Section

    private var logActivitySection: some View {
        Section {
            // Activity type picker
            HStack {
                Image(systemName: iconForActivity(selectedActivity))
                    .foregroundColor(.orange)
                    .font(.title3)

                Picker("Activity Type", selection: $selectedActivity) {
                    ForEach(PhysicalActivityEvent.activityTypes, id: \.self) { type in
                        Label(type, systemImage: iconForActivity(type))
                            .tag(type)
                    }
                }
            }

            // Time picker
            DatePicker(
                "Time of Activity",
                selection: $selectedTime,
                displayedComponents: .hourAndMinute
            )

            // Log button
            Button {
                logActivity()
            } label: {
                HStack {
                    Spacer()
                    if showSuccess {
                        Label("Logged!", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .fontWeight(.semibold)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Label("Log Activity", systemImage: "plus.circle.fill")
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(showSuccess ? .green : .blue)
            .controlSize(.large)
            .disabled(showSuccess)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        } header: {
            Text("Log Physical Activity")
        } footer: {
            Text("Record when you performed physical activity today.")
        }
    }

    // MARK: - Recent Logs Section

    @ViewBuilder
    private var recentLogsSection: some View {
        Section {
            if recentLogs.isEmpty {
                Label {
                    Text("No activities logged today.")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } icon: {
                    Image(systemName: "clock")
                        .foregroundColor(.gray)
                }
            } else {
                ForEach(recentLogs.reversed(), id: \.timestampMs) { log in
                    HStack {
                        Image(systemName: iconForActivity(log.activityType))
                            .foregroundColor(.orange)
                            .font(.title3)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(log.activityType)
                                .font(.body.weight(.medium))
                            Text("At \(formattedTime(ms: log.timeOfDayMs))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                    }
                }
            }
        } header: {
            Text("Recent Logs")
        } footer: {
            if !recentLogs.isEmpty {
                Text("\(recentLogs.count) activit\(recentLogs.count == 1 ? "y" : "ies") logged today")
            }
        }
    }

    // MARK: - Actions

    private func logActivity() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let timeMs = Int64(selectedTime.timeIntervalSince1970 * 1000)

        let event = PhysicalActivityEvent(
            timestampMs: nowMs,
            activityType: selectedActivity,
            timeOfDayMs: timeMs
        )

        appState.dataManager.writePhysicalActivityEvent(event)
        recentLogs.append(event)

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Show success state
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            showSuccess = true
        }

        // Reset after a delay so the user can log again
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showSuccess = false
            }
            // Reset time to "now" for the next entry
            selectedTime = Date()
        }
    }

    // MARK: - Helpers

    private func iconForActivity(_ type: String) -> String {
        switch type {
        case "Running": return "figure.run"
        case "Bike":    return "bicycle"
        case "Other":   return "figure.mixed.cardio"
        default:        return "figure.run"
        }
    }

    private func formattedTime(ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}
