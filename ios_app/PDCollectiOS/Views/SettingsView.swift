import SwiftUI
import AVFoundation

/// Settings screen — analogous to Android's SettingsActivity.
/// Provides controls to start/stop data collection, manage the face-camera service,
/// inspect raw data files, and reset participant consent.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showResetAlert    = false
    @State private var showDeleteAlert   = false
    @State private var cameraStatus      = ""

    private var profile: UserProfile { appState.userProfile }

    var body: some View {
        NavigationStack {
            Form {

                // MARK: - Collection Toggle (like Android's start/stop button)
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Data Collection")
                                .fontWeight(.medium)
                            Text(appState.isCollecting
                                 ? "Sensors, touch, and app events are being recorded."
                                 : "Collection is paused.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get:  { appState.isCollecting },
                            set:  { appState.isCollecting = $0 }
                        ))
                        .labelsHidden()
                    }
                } header: {
                    Label("Passive Collection", systemImage: "record.circle")
                }

                // MARK: - Face Camera
                Section {
                    HStack {
                        Label("Front Camera (Face Distance)", systemImage: "camera.fill")
                        Spacer()
                        statusBadge(running: appState.faceDistance.isRunning)
                    }

                    if appState.faceDistance.isRunning {
                        if let s = appState.faceDistance.lastSample {
                            LabeledContent("Last Ratio",
                                           value: String(format: "%.3f", s.distanceRatio))
                            LabeledContent("Roll / Yaw",
                                           value: String(format: "%.1f° / %.1f°", s.roll, s.yaw))
                        }
                        LabeledContent("Samples today",
                                       value: "\(appState.faceDistance.samplesCollected)")
                    } else {
                        Button("Enable Camera Access") { requestCamera() }
                            .font(.caption)
                    }
                } header: {
                    Label("Face Distance Service", systemImage: "face.dashed")
                }

                // MARK: - Passive Sensors Status
                Section {
                    HStack {
                        Label("Passive Sensors (100 Hz)", systemImage: "wave.3.right")
                        Spacer()
                        statusBadge(running: appState.passiveSensor.isRunning)
                    }
                    LabeledContent("Readings today",
                                   value: "\(appState.passiveSensor.totalReadingsToday)")
                } header: {
                    Label("Sensor Service", systemImage: "gyroscope")
                }

                // MARK: - Participant Info
                Section {
                    LabeledContent("Participant ID", value: profile.userId)
                        .font(.system(.body, design: .monospaced))
                    LabeledContent("Age",  value: profile.age.isEmpty  ? "–" : profile.age)
                    LabeledContent("Gender", value: profile.gender.isEmpty ? "–" : profile.gender)
                    LabeledContent("Dominant Hand", value: profile.dominantHand)
                    LabeledContent("PD Affected Side", value: profile.affectedSide)
                    if !profile.medications.isEmpty {
                        LabeledContent("Medications",
                                       value: profile.medications.joined(separator: ", "))
                    }
                } header: {
                    Label("Participant Profile", systemImage: "person.fill")
                }

                // MARK: - Danger Zone (matches Android's SettingsActivity reset / stop)
                Section {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("Delete All Collected Data", systemImage: "trash")
                    }

                    Button(role: .destructive) {
                        showResetAlert = true
                    } label: {
                        Label("Reset Consent & Start Over", systemImage: "arrow.counterclockwise")
                    }
                } header: {
                    Label("Danger Zone", systemImage: "exclamationmark.triangle")
                }

                // MARK: - App Info
                Section {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Branch",  value: "iphone")
                    LabeledContent("Build",   value: buildNumber)
                } header: {
                    Label("About", systemImage: "info.circle")
                }
            }
            .navigationTitle("Settings")
            .alert("Delete All Data?", isPresented: $showDeleteAlert) {
                Button("Delete Everything", role: .destructive) {
                    appState.stopCollection()
                    appState.dataManager.deleteAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all sensor readings, test results, and surveys. This cannot be undone.")
            }
            .alert("Reset & Withdraw?", isPresented: $showResetAlert) {
                Button("Reset", role: .destructive) { resetConsent() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will stop collection, delete all data, and return you to the consent screen.")
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statusBadge(running: Bool) -> some View {
        Label(running ? "Running" : "Stopped",
              systemImage: running ? "circle.fill" : "circle")
            .font(.caption)
            .foregroundColor(running ? .green : .secondary)
    }

    private func requestCamera() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if granted { appState.startFaceDistance() }
            }
        }
    }

    private func resetConsent() {
        appState.stopCollection()
        appState.dataManager.deleteAllData()
        appState.userProfile.clearAll()
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
    }
}
