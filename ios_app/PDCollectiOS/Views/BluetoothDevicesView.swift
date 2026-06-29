import SwiftUI

/// Bluetooth device management view — scan, pair, and monitor BLE sensors.
struct BluetoothDevicesView: View {
    @ObservedObject var btManager: BluetoothManager
    @ObservedObject var hr: HRBluetoothService
    @ObservedObject var beanie: BeanieBluetoothService

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
                        Label("Skin Temp", systemImage: "thermometer.medium")
                            .foregroundColor(.dopaxOrange)
                        Spacer()
                        Text(beanie.tskinC > 0 ? String(format: "%.1f °C", beanie.tskinC) : "Waiting...")
                            .fontWeight(.semibold)
                            .foregroundColor(.dopaxOrange)
                    }

                    if beanie.heatFlux != 0 {
                        LabeledContent("Heat Flux",
                                       value: String(format: "%.2f cal/s", beanie.heatFlux))
                    }

                    LabeledContent("Inner / Outer",
                                   value: String(format: "%.1f / %.1f °C", beanie.innerC, beanie.outerC))

                    if let bat = beanie.batteryPct {
                        HStack {
                            Label("Battery", systemImage: bat > 20 ? "battery.75percent" : "battery.25percent")
                            Spacer()
                            Text("\(bat)%")
                                .foregroundColor(bat > 20 ? .green : .red)
                        }
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
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statusDot(active: Bool) -> some View {
        Circle()
            .fill(active ? Color.green : Color.gray.opacity(0.4))
            .frame(width: 10, height: 10)
    }
}
