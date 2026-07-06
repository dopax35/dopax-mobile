import Foundation
import CoreBluetooth

/// Handles BLE Heart Rate Profile communication.
/// Acts as a CBPeripheralDelegate for the HR peripheral.
class HRBluetoothService: NSObject, ObservableObject, CBPeripheralDelegate {
    
    // MARK: - Published State
    
    @Published var isConnected = false
    @Published var currentBPM: Int = 0
    @Published var currentHRV: Float = 0
    @Published var deviceName: String = ""
    @Published var status: BLEDeviceStatus = .idle
    
    // MARK: - Internal
    
    var dataManager: DataManager?
    
    // BLE UUIDs
    private static let hrServiceUUID = CBUUID(string: "180D")
    private static let hrMeasurementUUID = CBUUID(string: "2A37")
    
    // HRV sliding window (60 seconds)
    private var rrIntervalWindow: [(timestamp: Int64, rr: Int)] = []
    
    func reset() {
        isConnected = false
        currentBPM = 0
        currentHRV = 0
        status = .idle
        rrIntervalWindow.removeAll()
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            status = .disconnected
            return
        }
        if let service = peripheral.services?.first(where: { $0.uuid == Self.hrServiceUUID }) {
            peripheral.discoverCharacteristics([Self.hrMeasurementUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { return }
        if let characteristic = service.characteristics?.first(where: { $0.uuid == Self.hrMeasurementUUID }) {
            peripheral.setNotifyValue(true, for: characteristic)
            isConnected = true
            status = .ready
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil,
              characteristic.uuid == Self.hrMeasurementUUID,
              let data = characteristic.value else { return }
        parseHRMeasurement(data, deviceAddress: peripheral.identifier.uuidString)
    }
    
    // MARK: - HR Parsing (Bluetooth HRP Spec)
    
    private func parseHRMeasurement(_ data: Data, deviceAddress: String) {
        guard data.count >= 2 else { return }
        let bytes = [UInt8](data)
        let flags = bytes[0]
        let hrFormat16bit = (flags & 0x01) != 0
        let rrPresent = (flags & 0x10) != 0
        
        let bpm: Int
        var rrOffset: Int
        
        if hrFormat16bit {
            guard bytes.count >= 3 else { return }
            bpm = Int(bytes[1]) | (Int(bytes[2]) << 8)
            rrOffset = 3
        } else {
            bpm = Int(bytes[1])
            rrOffset = 2
        }
        
        var rrIntervals: [Int] = []
        if rrPresent {
            while rrOffset + 1 < bytes.count {
                let rr = Int(bytes[rrOffset]) | (Int(bytes[rrOffset + 1]) << 8)
                // RR value is in 1/1024 seconds, convert to ms
                rrIntervals.append((rr * 1000) / 1024)
                rrOffset += 2
            }
        }
        
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        
        // Update sliding window
        if !rrIntervals.isEmpty {
            for rr in rrIntervals {
                rrIntervalWindow.append((timestamp: timestamp, rr: rr))
            }
        }
        // Remove intervals older than 60s
        let windowLimit = timestamp - 60000
        rrIntervalWindow.removeAll { $0.timestamp < windowLimit }
        
        let hrv = calculateRMSSD(rrIntervalWindow.map(\.rr))
        
        DispatchQueue.main.async {
            self.currentBPM = bpm
            self.currentHRV = hrv
        }
        
        // Log to CSV
        let reading = HeartRateReading(
            timestamp: timestamp,
            bpm: bpm,
            rrIntervals: rrIntervals,
            deviceAddress: deviceAddress,
            deviceName: deviceName
        )
        dataManager?.writeHeartRateData(reading)
    }
    
    /// RMSSD: Root Mean Square of Successive Differences
    private func calculateRMSSD(_ intervals: [Int]) -> Float {
        guard intervals.count >= 2 else { return 0 }
        var sumSqDiff = 0.0
        for i in 1..<intervals.count {
            let diff = Double(intervals[i] - intervals[i - 1])
            sumSqDiff += diff * diff
        }
        return Float(sqrt(sumSqDiff / Double(intervals.count - 1)))
    }
}


