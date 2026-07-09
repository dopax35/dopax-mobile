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
    @State private var isImporting = false
    @State private var importMessage: String?
    /// StravaManager publishes isConnected, so this button's label updates
    /// automatically the moment the OAuth callback completes — no polling.
    @ObservedObject private var stravaManager = StravaManager.shared

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                importSection
                logActivitySection
                recentLogsSection
            }
            .navigationTitle("Activity Log")
        }
    }

    // MARK: - Import Section

    private var importSection: some View {
        Section {
            Button {
                importFromHealthKit()
            } label: {
                Label("Import from Apple Health", systemImage: "heart.fill")
            }
            .disabled(isImporting)

            Button {
                if stravaManager.isConnected {
                    importFromStrava()
                } else {
                    stravaManager.startAuth()
                }
            } label: {
                Label(
                    stravaManager.isConnected ? "Import from Strava" : "Connect Strava",
                    systemImage: "figure.run.circle.fill"
                )
            }
            .disabled(isImporting)

            if isImporting {
                HStack {
                    ProgressView()
                    Text("Importing…").foregroundColor(.secondary)
                }
            }
            if let importMessage {
                Text(importMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("Import Workouts")
        } footer: {
            Text("Pull in workouts you already logged elsewhere instead of re-entering them by hand.")
        }
    }

    // MARK: - Log Activity Section

    private var logActivitySection: some View {
        Section {
            // Activity type picker
            HStack {
                Image(systemName: iconForActivity(selectedActivity))
                    .foregroundColor(.dopaxOrange)
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
                            .foregroundColor(.dopaxStatusSuccess)
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
            .tint(showSuccess ? .dopaxStatusSuccess : .dopaxBlue)
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
                        .foregroundColor(.dopaxGray50)
                }
            } else {
                ForEach(recentLogs.reversed(), id: \.timestampMs) { log in
                    HStack {
                        Image(systemName: iconForActivity(log.activityType))
                            .foregroundColor(.dopaxOrange)
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
                            .foregroundColor(.dopaxStatusSuccess)
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

    /// Imports recent Apple Health workouts, skipping any already imported
    /// on a previous run (per ImportedActivityStore) so re-importing an
    /// overlapping look-back window doesn't create duplicate rows.
    private func importFromHealthKit() {
        isImporting = true
        importMessage = nil
        Task {
            if !appState.healthKitManager.isAuthorized {
                await appState.healthKitManager.requestAuthorization()
            }
            let workouts = await appState.healthKitManager.fetchRecentWorkouts(days: 7)
            await MainActor.run {
                var imported: [PhysicalActivityEvent] = []
                for w in workouts {
                    if let id = w.externalId, ImportedActivityStore.isAlreadyImported(source: "HealthKit", externalId: id) {
                        continue
                    }
                    appState.dataManager.writePhysicalActivityEvent(w)
                    if let id = w.externalId {
                        ImportedActivityStore.markImported(source: "HealthKit", externalId: id)
                    }
                    imported.append(w)
                }
                recentLogs.append(contentsOf: imported.filter { isToday($0.timeOfDayMs) })
                importMessage = workouts.isEmpty
                    ? "No recent Apple Health workouts found."
                    : (imported.isEmpty
                        ? "No new Apple Health workouts to import (already imported)."
                        : "Imported \(imported.count) workout(s) from Apple Health.")
                isImporting = false
            }
        }
    }

    /// Imports recent Strava activities, skipping any already imported on a
    /// previous run (per ImportedActivityStore) so re-importing an
    /// overlapping look-back window doesn't create duplicate rows.
    private func importFromStrava() {
        isImporting = true
        importMessage = nil
        Task {
            let activities = await stravaManager.fetchRecentActivities(days: 7)
            await MainActor.run {
                var imported: [PhysicalActivityEvent] = []
                for a in activities {
                    if let id = a.externalId, ImportedActivityStore.isAlreadyImported(source: "Strava", externalId: id) {
                        continue
                    }
                    appState.dataManager.writePhysicalActivityEvent(a)
                    if let id = a.externalId {
                        ImportedActivityStore.markImported(source: "Strava", externalId: id)
                    }
                    imported.append(a)
                }
                recentLogs.append(contentsOf: imported.filter { isToday($0.timeOfDayMs) })
                importMessage = activities.isEmpty
                    ? "No recent Strava activities found."
                    : (imported.isEmpty
                        ? "No new Strava activities to import (already imported)."
                        : "Imported \(imported.count) activit\(imported.count == 1 ? "y" : "ies") from Strava.")
                isImporting = false
            }
        }
    }

    // MARK: - Helpers

    private func isToday(_ ms: Int64) -> Bool {
        Calendar.current.isDateInToday(Date(timeIntervalSince1970: Double(ms) / 1000.0))
    }

    private func iconForActivity(_ type: String) -> String {
        switch type {
        case "Running":         return "figure.run"
        case "Bike":             return "bicycle"
        // Swimming/Weight Training/Other are still best-guess SF Symbol
        // names for the newly added activity types — Image(systemName:)
        // fails silently (blank icon) on a bad name rather than a build
        // error, so verify these against Xcode's SF Symbols picker during
        // integration and swap if needed.
        case "Swimming":         return "figure.pool.swim"
        case "Weight Training":  return "dumbbell.fill"
        // figure.pilates was added in SF Symbols 5 (iOS 17) — this app's
        // deployment target is iOS 16.0 (project.pbxproj), so that symbol
        // would render blank on any iOS 16 device. figure.mind.and.body has
        // been available since iOS 14 and reads reasonably for Pilates.
        case "Pilates":          return "figure.mind.and.body"
        case "Other":            return "figure.mixed.cardio"
        default:                 return "figure.run"
        }
    }

    private func formattedTime(ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}
