import SwiftUI

/// Medication intake logging view — lets the user log when they took each medication.
/// Ported from the Android dialog-based flow into a native SwiftUI Form.
struct MedicationLogView: View {
    @EnvironmentObject var appState: AppState

    // MARK: - State

    /// Medication currently being logged (drives the time-picker sheet).
    @State private var selectedMedication: Medication?
    /// User-selected time of intake.
    @State private var selectedTime = Date()
    /// Today's logged events (local, in-memory for the current session).
    @State private var recentLogs: [MedicationEvent] = []
    /// Name of the medication that was just logged (drives checkmark animation).
    @State private var justLoggedMed: String?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                medicationsSection
                recentLogsSection
            }
            .navigationTitle("Medication Log")
            .sheet(item: $selectedMedication) { med in
                timePickerSheet(for: med)
            }
        }
    }

    // MARK: - Medications List Section

    @ViewBuilder
    private var medicationsSection: some View {
        let meds = appState.userProfile.medications

        Section {
            if meds.isEmpty {
                Label {
                    Text("No medications configured.\nAdd them in Settings → Profile.")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } icon: {
                    Image(systemName: "pill.fill")
                        .foregroundColor(.dopaxGray50)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(meds) { med in
                    medicationRow(med)
                }
            }
        } header: {
            Text("Your Medications")
        }
    }

    private func medicationRow(_ med: Medication) -> some View {
        HStack {
            Image(systemName: "pill.fill")
                .foregroundColor(.dopaxBlue)
                .font(.title3)

            VStack(alignment: .leading) {
                Text(med.name).font(.body)
                if !med.dosage.isEmpty {
                    Text(med.dosage).font(.caption).foregroundColor(.secondary)
                }
            }

            Spacer()

            if justLoggedMed == med.name {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.dopaxStatusSuccess)
                    .font(.title2)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button {
                    selectedTime = Date()
                    selectedMedication = med
                } label: {
                    Label("Log Intake", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Recent Logs Section

    @ViewBuilder
    private var recentLogsSection: some View {
        Section {
            if recentLogs.isEmpty {
                Label {
                    Text("No medications logged today.")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } icon: {
                    Image(systemName: "clock")
                        .foregroundColor(.dopaxGray50)
                }
            } else {
                ForEach(recentLogs.reversed(), id: \.timestampMs) { log in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(log.medName)
                                .font(.body.weight(.medium))
                            if !log.dosage.isEmpty {
                                Text(log.dosage).font(.caption).foregroundColor(.secondary)
                            }
                            Text("Taken at \(formattedTime(ms: log.takenMs))")
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
                Text("\(recentLogs.count) intake\(recentLogs.count == 1 ? "" : "s") logged today")
            }
        }
    }

    // MARK: - Time Picker Sheet

    private func timePickerSheet(for med: Medication) -> some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "pill.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.dopaxBlue)

                Text("Log \(med.name)")
                    .font(.title2.weight(.semibold))

                Text("When did you take this medication?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                DatePicker(
                    "Time taken",
                    selection: $selectedTime,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()

                Spacer()
            }
            .padding(.top, 32)
            .navigationTitle("Log Intake")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        selectedMedication = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        logMedication(med)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private func logMedication(_ med: Medication) {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let takenMs = Int64(selectedTime.timeIntervalSince1970 * 1000)

        let event = MedicationEvent(
            timestampMs: nowMs,
            takenMs: takenMs,
            medName: med.name,
            dosage: med.dosage
        )

        appState.dataManager.writeMedicationEvent(event)
        appState.sessionManager.markTask(.medication)
        recentLogs.append(event)

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Dismiss sheet
        selectedMedication = nil

        // Show success checkmark animation
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            justLoggedMed = med.name
        }

        // Clear checkmark after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                justLoggedMed = nil
            }
        }
    }

    // MARK: - Helpers

    private func formattedTime(ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}
