import SwiftUI

/// Today's medication, as a bottom sheet (Figma 475:2).
///
/// The CSV write path is untouched: logging still calls
/// `DataManager.writeMedicationEvent` exactly as the old form did. What is new
/// is that the sheet can *show* what was logged today after it has been closed
/// and reopened, which the in-memory list could not.
struct MedicationSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var log = MedicationDayLog()

    @State private var adding = false
    @State private var editing: LoggedDose?

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.dopaxGray30)
                .frame(width: 40, height: 4)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 0) {
                Text("Today's medication")
                    .font(.dopax(22, .bold))
                    .foregroundColor(.dopaxBlack90)
                    .padding(.top, 22)

                Text(subtitle)
                    .font(.dopax(13.5))
                    .foregroundColor(.dopaxBlack70)
                    .padding(.top, 4)

                doses
                    .padding(.top, 18)

                if log.doses.isEmpty {
                    Text("Nothing logged yet today.")
                        .font(.dopax(14))
                        .foregroundColor(.onboardingTextTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 22)
                }

                Button { adding = true } label: {
                    Text("Add medication")
                        .font(.dopax(16, .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.sheetAccentCoral)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.top, 22)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .onAppear { log.load() }
        .sheet(isPresented: $adding) {
            MedicationTimePicker(medications: appState.userProfile.medications,
                                 title: "Log a dose") { med, time in
                record(med, at: time)
                adding = false
            }
        }
        .sheet(item: $editing) { dose in
            MedicationTimePicker(medications: appState.userProfile.medications,
                                 preselected: dose.name,
                                 initialTime: dose.taken,
                                 title: "Correct the time") { med, time in
                record(med, at: time, correcting: dose)
                editing = nil
            }
        }
    }

    private var subtitle: String {
        let day = Self.dayFormatter.string(from: Date())
        let count = log.doses.count
        return "\(day) · \(count) dose\(count == 1 ? "" : "s") logged"
    }

    private var doses: some View {
        VStack(spacing: 10) {
            ForEach(log.doses) { dose in
                HStack(spacing: 14) {
                    Text(Self.timeFormatter.string(from: dose.taken))
                        .font(.dopax(13, .semibold))
                        .foregroundColor(.onboardingAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(dose.name)
                            .font(.dopax(15, .semibold))
                            .foregroundColor(.dopaxBlack90)
                        Text(dose.dosage)
                            .font(.dopax(12.5))
                            .foregroundColor(.dopaxBlack70)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button { editing = dose } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.dopaxBlack70)
                    }
                    .accessibilityLabel("Correct the time for \(dose.name)")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.onboardingCream)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    /// Appends an intake event. A correction appends too rather than rewriting
    /// history — the CSV the study reads is append-only, and losing the first
    /// reading to hide a typo is the worse of the two failures.
    private func record(_ med: Medication, at time: Date, correcting: LoggedDose? = nil) {
        let event = MedicationEvent(timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
                                    takenMs: Int64(time.timeIntervalSince1970 * 1000),
                                    medName: med.name,
                                    dosage: med.dosage)
        appState.dataManager.writeMedicationEvent(event)
        appState.sessionManager.markTask(.medication)

        if let correcting {
            log.replace(correcting, with: LoggedDose(name: med.name, dosage: med.dosage, taken: time))
        } else {
            log.add(LoggedDose(name: med.name, dosage: med.dosage, taken: time))
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("Hmm")
        return formatter
    }()
}

// MARK: - Dose list

struct LoggedDose: Identifiable, Codable, Equatable {
    var id = UUID()
    let name: String
    let dosage: String
    let taken: Date
}

/// What the sheet shows, kept separately from the CSV.
///
/// The CSV is the record of truth and is append-only; this is a display cache
/// so reopening the sheet does not claim nothing was logged. It is rebuilt each
/// day and never read by anything that ships data.
final class MedicationDayLog: ObservableObject {
    @Published private(set) var doses: [LoggedDose] = []

    private let defaults: UserDefaults
    private var dayKey = ""

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() {
        let today = Self.key(for: Date())
        guard today != dayKey || doses.isEmpty else { return }
        dayKey = today
        guard let data = defaults.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode([LoggedDose].self, from: data) else {
            doses = []
            return
        }
        doses = stored.sorted { $0.taken < $1.taken }
    }

    func add(_ dose: LoggedDose) {
        doses.append(dose)
        doses.sort { $0.taken < $1.taken }
        persist()
    }

    func replace(_ old: LoggedDose, with new: LoggedDose) {
        guard let index = doses.firstIndex(of: old) else { return add(new) }
        doses[index] = new
        doses.sort { $0.taken < $1.taken }
        persist()
    }

    private var storageKey: String { "medication_day_log_\(dayKey)" }

    private func persist() {
        guard let data = try? JSONEncoder().encode(doses) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func key(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Picker

private struct MedicationTimePicker: View {
    let medications: [Medication]
    var preselected: String?
    var initialTime: Date = Date()
    let title: String
    let onConfirm: (Medication, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Medication?
    @State private var time = Date()

    var body: some View {
        NavigationStack {
            Group {
                if medications.isEmpty {
                    empty
                } else {
                    form
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        if let selection { onConfirm(selection, time) }
                    }
                    .fontWeight(.semibold)
                    .disabled(selection == nil)
                }
            }
        }
        .onAppear {
            time = initialTime
            selection = medications.first { $0.name == preselected } ?? medications.first
        }
        .presentationDetents([.medium])
    }

    private var form: some View {
        Form {
            Section("Medication") {
                Picker("Medication", selection: $selection) {
                    ForEach(medications) { med in
                        Text(med.dosage.isEmpty ? med.name : "\(med.name) · \(med.dosage)")
                            .tag(Optional(med))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Time taken") {
                DatePicker("Time taken", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "pills")
                .font(.system(size: 40))
                .foregroundColor(.dopaxGray50)
            Text("No medications on your list yet")
                .font(.dopax(16, .semibold))
                .foregroundColor(.dopaxBlack90)
            Text("Add them under Profile, then come back to log a dose.")
                .font(.dopax(14))
                .foregroundColor(.dopaxBlack70)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}
