import SwiftUI
import AVFoundation

/// Settings screen — analogous to Android's SettingsActivity.
/// Provides controls to start/stop data collection, manage the face-camera service,
/// inspect raw data files, and reset participant consent.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    @AppStorage("autoUploadEnabled") private var autoUploadEnabled = false
    @State private var showResetAlert    = false
    @State private var showDeleteAlert   = false
    @State private var cameraStatus      = ""
    @State private var isUploading       = false
    @State private var editingMedication: Medication?


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

                // MARK: - Bluetooth Devices
                Section {
                    NavigationLink {
                        BluetoothDevicesView(
                            btManager: appState.bluetoothManager,
                            hr: appState.bluetoothManager.hrService,
                            beanie: appState.bluetoothManager.beanieService
                        )
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Manage Devices")
                                    .fontWeight(.medium)
                                Text(bluetoothStatusSummary)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            bluetoothStatusDot
                        }
                    }
                } header: {
                    Label("Bluetooth Devices", systemImage: "antenna.radiowaves.left.and.right")
                }

                // MARK: - Cloud Upload
                Section {
                    Toggle(isOn: $autoUploadEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Auto Upload")
                                .fontWeight(.medium)
                            Text(autoUploadEnabled
                                 ? "Data uploads automatically in the background."
                                 : "Upload manually from the My Data tab.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if autoUploadEnabled {
                        Button {
                            isUploading = true
                            Task {
                                await BackgroundCollectionManager.uploadPendingDates(
                                    dataManager: appState.dataManager
                                )
                                await MainActor.run { isUploading = false }
                            }
                        } label: {
                            HStack {
                                Label("Upload Now", systemImage: "icloud.and.arrow.up")
                                if isUploading {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isUploading)
                    }
                } header: {
                    Label("Cloud Upload", systemImage: "icloud")
                }

                // MARK: - Participant Info
                Section {
                    LabeledContent("Participant ID", value: profile.userId)
                        .font(.system(.body, design: .monospaced))
                    LabeledContent("Age",  value: profile.age.isEmpty  ? "–" : profile.age)
                    LabeledContent("Gender", value: profile.gender.isEmpty ? "–" : profile.gender)
                    LabeledContent("Dominant Hand", value: profile.dominantHand)
                    LabeledContent("PD Affected Side", value: profile.affectedSide)
                } header: {
                    Label("Participant Profile", systemImage: "person.fill")
                }

                // MARK: - Medications (editable)
                Section {
                    ForEach(profile.medications) { med in
                        Button {
                            editingMedication = med
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(med.name).foregroundColor(.primary)
                                    if !med.dosage.isEmpty {
                                        Text(med.dosage).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "pencil").foregroundColor(.blue)
                            }
                        }
                    }
                    .onDelete { idx in
                        var meds = profile.medications
                        meds.remove(atOffsets: idx)
                        profile.medications = meds
                    }

                    Button("Add Medication") {
                        let newMed = Medication(name: "", dosage: "")
                        editingMedication = newMed
                    }
                } header: {
                    Label("Medications", systemImage: "pill.fill")
                } footer: {
                    Text("Tap to edit · Swipe left to delete")
                        .font(.caption)
                }
                
                // MARK: - Keystroke Logging
                Section {
                    let todayKey = "keystroke_count_\(Date().dateKeyString)"
                    let count = UserDefaults(suiteName: "group.com.oriw.pdcollect.ios1.shared")?.integer(forKey: todayKey) ?? 0
                    
                    LabeledContent("Keys logged today", value: "\(count)")
                    
                    Button("Keyboard Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } header: {
                    Label("Keystroke Keyboard", systemImage: "keyboard")
                } footer: {
                    Text("Ensure PDCollectKeyboard is enabled in Settings and selected when typing.")
                }



                // MARK: - Danger Zone (matches Android's SettingsActivity reset / stop)
                Section {
                    Button(role: .destructive) {
                        appState.authManager.signOut()
                        resetConsent()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    
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
            .sheet(item: $editingMedication) { med in
                MedicationEditSheet(medication: med, profile: profile)
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

    private var bluetoothStatusSummary: String {
        let hr = appState.bluetoothManager.hrService
        let beanie = appState.bluetoothManager.beanieService
        var parts: [String] = []
        if hr.isConnected { parts.append("❤️ \(hr.deviceName)") }
        if beanie.isConnected { parts.append("🌡️ \(beanie.deviceName)") }
        if parts.isEmpty { return "No devices paired" }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var bluetoothStatusDot: some View {
        let hr = appState.bluetoothManager.hrService
        let beanie = appState.bluetoothManager.beanieService
        let anyConnected = hr.isConnected || beanie.isConnected
        Circle()
            .fill(anyConnected ? Color.green : Color.gray.opacity(0.4))
            .frame(width: 10, height: 10)
    }
}
