import Foundation
import CoreBluetooth

/// Handles BLE communication with the Beanie temperature/IMU sensor.
/// Acts as CBPeripheralDelegate for the Beanie peripheral.
class BeanieBluetoothService: NSObject, ObservableObject, CBPeripheralDelegate {

    // MARK: - Published State

    @Published var isConnected = false
    @Published var tskinC: Double = 0
    @Published var heatFlux: Double = 0
    @Published var innerC: Double = 0
    @Published var outerC: Double = 0
    @Published var batteryPct: Int? = nil
    @Published var deviceName: String = ""
    @Published var deviceAddress: String = ""
    @Published var status: BLEDeviceStatus = .idle

    // MARK: - Internal

    var dataManager: DataManager?
    let parser = BeaniePacketParser(profile: BeanieRegistry.defaultProfile)

    // BLE UUIDs
    private static let beanieServiceUUID = CBUUID(string: "12345678-90AB-4CDE-8123-1234567890AB")
    private static let dataCharUUID = CBUUID(string: "12345679-90AB-4CDE-8123-1234567890AB")
    private static let cmdCharUUID = CBUUID(string: "1234567A-90AB-4CDE-8123-1234567890AB")

    // Characteristics
    private var dataCharacteristic: CBCharacteristic?
    private var cmdCharacteristic: CBCharacteristic?
    private weak var peripheral: CBPeripheral?

    // Stream management
    private var useReadPolling = false
    private var readPollTimer: Timer?
    private var streamWarmupTimer: Timer?
    private var receivedFrame = false
    private var liveStartRetryCount = 0
    private static let maxLiveStartRetries = 2
    private static let readPollInterval: TimeInterval = 1.5
    private static let streamWarmupTimeout: TimeInterval = 10.0

    // Command write queue
    private var commandQueue: [Data] = []
    private var commandWriteInFlight = false

    func reset() {
        isConnected = false
        status = .idle
        tskinC = 0
        heatFlux = 0
        innerC = 0
        outerC = 0
        batteryPct = nil
        dataCharacteristic = nil
        cmdCharacteristic = nil
        peripheral = nil
        useReadPolling = false
        receivedFrame = false
        liveStartRetryCount = 0
        commandQueue.removeAll()
        commandWriteInFlight = false
        readPollTimer?.invalidate()
        readPollTimer = nil
        streamWarmupTimer?.invalidate()
        streamWarmupTimer = nil
        parser.resetBuffer()
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            status = .disconnected
            return
        }
        self.peripheral = peripheral

        if let service = peripheral.services?.first(where: { $0.uuid == Self.beanieServiceUUID }) {
            peripheral.discoverCharacteristics([Self.dataCharUUID, Self.cmdCharUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { return }

        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case Self.dataCharUUID:
                dataCharacteristic = characteristic
            case Self.cmdCharUUID:
                cmdCharacteristic = characteristic
            default:
                break
            }
        }

        // Update profile based on device name
        let profile = BeanieRegistry.profileForDevice(deviceName)
        parser.updateProfile(profile)

        // Setup data stream
        setupDataStream(peripheral: peripheral)
    }

    private func setupDataStream(peripheral: CBPeripheral) {
        guard let dataChar = dataCharacteristic else { return }

        if useReadPolling && dataChar.properties.contains(.read) {
            // Go straight to read polling
            isConnected = true
            status = .ready
            startReadPolling(peripheral: peripheral)
            return
        }

        // Try notifications first
        if dataChar.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: dataChar)
            scheduleStreamWarmupTimeout(peripheral: peripheral)
        } else if dataChar.properties.contains(.indicate) {
            peripheral.setNotifyValue(true, for: dataChar)
            scheduleStreamWarmupTimeout(peripheral: peripheral)
        } else if dataChar.properties.contains(.read) {
            useReadPolling = true
            isConnected = true
            status = .ready
            startReadPolling(peripheral: peripheral)
        }

        isConnected = true
        status = .ready

        // Send live-start command sequence
        if cmdCharacteristic != nil {
            sendLiveStartSequence()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if error != nil {
            // Notification setup failed, try read polling
            if let dataChar = dataCharacteristic, dataChar.properties.contains(.read) {
                useReadPolling = true
                startReadPolling(peripheral: peripheral)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value, !data.isEmpty else { return }

        if characteristic.uuid == Self.dataCharUUID {
            receivedFrame = true
            streamWarmupTimer?.invalidate()
            processIncomingData(data)

            // Schedule next read if polling
            if useReadPolling {
                scheduleNextRead(peripheral: peripheral)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        commandWriteInFlight = false
        pumpCommandQueue()
    }

    // MARK: - Data Processing

    private func processIncomingData(_ data: Data) {
        let frames = parser.processData(data)
        let profileName = BeanieRegistry.profileNameForDevice(deviceName)

        for frame in frames {
            switch frame {
            case .temperature(let sample):
                DispatchQueue.main.async {
                    self.tskinC = sample.tskinC
                    self.heatFlux = sample.heatFluxCalPerSec
                    self.innerC = sample.innerC
                    self.outerC = sample.outerC
                }

                let reading = BeanieTemperatureReading(
                    timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                    deviceName: deviceName,
                    deviceAddress: deviceAddress,
                    profileName: profileName,
                    innerC: sample.innerC,
                    outerC: sample.outerC,
                    tskinC: sample.tskinC,
                    heatFluxCalPerSec: sample.heatFluxCalPerSec,
                    batteryPct: batteryPct
                )
                dataManager?.writeBeanieTemperatureData(reading)

            case .imu(let samples):
                let readings = samples.map { sample in
                    BeanieIMUReading(
                        timestamp: sample.timestamp,
                        deviceName: deviceName,
                        deviceAddress: deviceAddress,
                        axRaw: sample.axRaw, ayRaw: sample.ayRaw, azRaw: sample.azRaw,
                        gxRaw: sample.gxRaw, gyRaw: sample.gyRaw, gzRaw: sample.gzRaw,
                        axG: sample.axG, ayG: sample.ayG, azG: sample.azG,
                        accelMagG: sample.accelMagG,
                        gxDps: sample.gxDps, gyDps: sample.gyDps, gzDps: sample.gzDps,
                        gyroMagDps: sample.gyroMagDps
                    )
                }
                dataManager?.writeBeanieImuData(readings)

            case .battery(let pct):
                DispatchQueue.main.async {
                    self.batteryPct = pct
                }
            }
        }
    }

    // MARK: - Live Start Command Sequence

    private func sendLiveStartSequence() {
        // 0xA4 — Stop/reset recording
        enqueueCommand(Data([0xA4]))

        // 0x02 + timestamp — Set RTC clock
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.enqueueCommand(self?.buildSetTimePayload() ?? Data())
        }

        // 0x04 — Resume/start live recording
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.enqueueCommand(Data([0x04]))
        }
    }

    private func buildSetTimePayload() -> Data {
        let now = Date()
        let calendar = Calendar.current
        let month = calendar.component(.month, from: now)
        let day = calendar.component(.day, from: now)
        let year = calendar.component(.year, from: now) % 100
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let second = calendar.component(.second, from: now)

        let timeString = String(format: "%02d%02d%02d%02d%02d%02d", month, day, year, hour, minute, second)
        var payload = Data([0x02])
        payload.append(timeString.data(using: .ascii) ?? Data())
        return payload
    }

    // MARK: - Command Queue

    private func enqueueCommand(_ data: Data) {
        guard !data.isEmpty else { return }
        commandQueue.append(data)
        pumpCommandQueue()
    }

    private func pumpCommandQueue() {
        guard !commandWriteInFlight,
              let peripheral = peripheral,
              let cmdChar = cmdCharacteristic,
              !commandQueue.isEmpty else { return }

        let payload = commandQueue.removeFirst()
        commandWriteInFlight = true
        peripheral.writeValue(payload, for: cmdChar, type: .withResponse)
    }

    // MARK: - Read Polling Fallback

    private func startReadPolling(peripheral: CBPeripheral) {
        readPollTimer?.invalidate()
        pollData(peripheral: peripheral)
    }

    private func scheduleNextRead(peripheral: CBPeripheral) {
        readPollTimer?.invalidate()
        readPollTimer = Timer.scheduledTimer(withTimeInterval: Self.readPollInterval, repeats: false) { [weak self] _ in
            self?.pollData(peripheral: peripheral)
        }
    }

    private func pollData(peripheral: CBPeripheral) {
        guard let dataChar = dataCharacteristic, useReadPolling else { return }
        peripheral.readValue(for: dataChar)
    }

    // MARK: - Stream Warmup

    private func scheduleStreamWarmupTimeout(peripheral: CBPeripheral) {
        streamWarmupTimer?.invalidate()
        streamWarmupTimer = Timer.scheduledTimer(withTimeInterval: Self.streamWarmupTimeout, repeats: false) { [weak self] _ in
            guard let self = self, !self.receivedFrame else { return }

            if self.liveStartRetryCount < Self.maxLiveStartRetries, self.cmdCharacteristic != nil {
                self.liveStartRetryCount += 1
                self.sendLiveStartSequence()
                self.scheduleStreamWarmupTimeout(peripheral: peripheral)
            } else if let dataChar = self.dataCharacteristic, dataChar.properties.contains(.read) {
                self.useReadPolling = true
                self.startReadPolling(peripheral: peripheral)
            }
        }
    }
}
