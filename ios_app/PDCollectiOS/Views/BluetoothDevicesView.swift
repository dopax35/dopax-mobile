import SwiftUI

/// Bluetooth device management view — scan, pair, and monitor BLE sensors.
struct BluetoothDevicesView: View {
    @ObservedObject var btManager: BluetoothManager
    @ObservedObject var hr: HRBluetoothService
    @ObservedObject var beanie: BeanieBluetoothService

    @State private var showPostureCalibration = false

    var body: some View {
        Form {
            // MARK: - Bluetooth Status
            if !btManager.isPoweredOn {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.dopaxOrange)
                        Text("Bluetooth is turned off. Enable it in Settings.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // MARK: - Heart Rate Monitor
            Section {
                // Current status
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if hr.deviceName.isEmpty {
                            Text("No device paired")
                                .foregroundColor(.secondary)
                        } else {
                            Text(hr.deviceName)
                                .fontWeight(.medium)
                            Text(hr.status.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    statusDot(active: hr.status == .ready)
                }

                // Live readings
                if hr.isConnected {
                    HStack {
                        Label("Heart Rate", systemImage: "heart.fill")
                            .foregroundColor(.red)
                        Spacer()
                        Text(hr.currentBPM > 0 ? "\(hr.currentBPM) bpm" : "Waiting...")
                            .fontWeight(.semibold)
                            .foregroundColor(.dopaxOrange)
                    }

                    if hr.currentHRV > 0 {
                        LabeledContent("HRV (RMSSD)",
                                       value: String(format: "%.0f ms", hr.currentHRV))
                    }
                }

                // Scan button
                Button {
                    btManager.scanForHRDevices()
                } label: {
                    Label(btManager.isScanning ? "Scanning..." : "Scan for HR Devices",
                          systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(btManager.isScanning || !btManager.isPoweredOn)

                // Discovered devices
                ForEach(btManager.discoveredHRDevices, id: \.id) { device in
                    Button {
                        btManager.connectHRDevice(id: device.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(device.name)
                                    .foregroundColor(.primary)
                                Text(device.id.uuidString.prefix(8) + "...")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "link")
                                .foregroundColor(.dopaxBlue)
                        }
                    }
                }

                // Disconnect button
                if !hr.deviceName.isEmpty {
                    Button(role: .destructive) {
                        btManager.disconnectHR()
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                }
            } header: {
                Label("Heart Rate Monitor", systemImage: "heart.fill")
            }

            // MARK: - Beanie Temperature Sensor
            Section {
                // Current status
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if beanie.deviceName.isEmpty {
                            Text("No device paired")
                                .foregroundColor(.secondary)
                        } else {
                            Text(beanie.deviceName)
                                .fontWeight(.medium)
                            Text(beanie.status.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    statusDot(active: beanie.status == .ready)
                }

                // Live readings
                if beanie.isConnected {
                    HStack {
                        Label("Skin Temperature", systemImage: "thermometer")
                            .foregroundColor(.dopaxOrange)
                        Spacer()
                        Text(String(format: "%.1f\u{00B0}C", beanie.tskinC))
                            .fontWeight(.semibold)
                            .foregroundColor(.dopaxOrange)
                    }

                    LabeledContent("Heat Flux",
                                   value: String(format: "%.2f cal/s", beanie.heatFlux))

                    if !beanie.activityLabel.isEmpty {
                        LabeledContent("Activity",
                                       value: String(format: "%@ (%.0f%%)",
                                                      beanie.activityLabel,
                                                      beanie.activityConfidence * 100))
                    }

                    if let battery = beanie.batteryPct {
                        LabeledContent("Battery", value: "\(battery)%")
                    }
                }

                // Scan button
                Button {
                    btManager.scanForBeanieDevices()
                } label: {
                    Label(btManager.isScanning ? "Scanning..." : "Scan for Beanie Devices",
                          systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(btManager.isScanning || !btManager.isPoweredOn)

                // Discovered devices
                ForEach(btManager.discoveredBeanieDevices, id: \.id) { device in
                    Button {
                        btManager.connectBeanieDevice(id: device.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(device.name)
                                    .foregroundColor(.primary)
                                Text(device.id.uuidString.prefix(8) + "...")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "link")
                                .foregroundColor(.dopaxBlue)
                        }
                    }
                }

                // Calibrate posture — only meaningful once a Beanie is paired.
                if !beanie.deviceName.isEmpty {
                    Button {
                        showPostureCalibration = true
                    } label: {
                        Label("Calibrate Posture", systemImage: "figure.stand")
                    }
                }

                // Disconnect button
                if !beanie.deviceName.isEmpty {
                    Button(role: .destructive) {
                        btManager.disconnectBeanie()
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                }
            } header: {
                Label("Beanie Temperature Sensor", systemImage: "thermometer")
            }
        }
        .navigationTitle("Bluetooth Devices")
        .sheet(isPresented: $showPostureCalibration) {
            PostureCalibrationView()
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statusDot(active: Bool) -> some View {
        Circle()
            .fill(active ? Color.dopaxStatusSuccess : Color.dopaxGray50.opacity(0.4))
            .frame(width: 10, height: 10)
    }
}
