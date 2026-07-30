import Foundation
import Combine
import SensorKit

/// Manages SensorKit reader access for Parkinson's Disease research.
/// Handles authorization requests and historical data retrieval for the 4 approved streams:
/// - Accelerometer
/// - RotationRate (gyroscope)
/// - KeyboardMetrics
/// - DeviceUsage
class SensorKitManager: NSObject, ObservableObject, SRSensorReaderDelegate {

    // MARK: - Published State
    @Published private(set) var isAvailable: Bool = false
    @Published private(set) var isFetching: Bool = false
    @Published private(set) var lastFetchDate: Date?
    @Published private(set) var authorizationStatuses: [String: String] = [:]
    @Published private(set) var sampleCountsToday: [String: Int] = [
        "accelerometer": 0,
        "rotationRate": 0,
        "keyboardMetrics": 0,
        "deviceUsage": 0
    ]

    // MARK: - Private Readers & Queues
    private var readers: [SRSensor: SRSensorReader] = [:]
    private let fetchQueue = DispatchQueue(label: "com.pdcollect.sensorkit-queue", qos: .utility)
    private weak var dataManager: DataManager?

    // Streams requested under Case-ID: 20926388
    private let approvedSensors: [SRSensor] = [
        .accelerometer,
        .rotationRate,
        .keyboardMetrics,
        .deviceUsage
    ]

    override init() {
        super.init()
        checkAvailabilityAndStatus()
    }

    // MARK: - Configuration & Status
    func configure(dataManager: DataManager) {
        self.dataManager = dataManager
        checkAvailabilityAndStatus()
    }

    func checkAvailabilityAndStatus() {
        guard #available(iOS 14.0, *) else {
            DispatchQueue.main.async { self.isAvailable = false }
            return
        }

        var statuses: [String: String] = [:]
        for sensor in approvedSensors {
            let reader = SRSensorReader(sensor: sensor)
            reader.delegate = self
            readers[sensor] = reader

            let statusString: String
            switch reader.authorizationStatus {
            case .authorized:
                statusString = "Authorized"
            case .denied:
                statusString = "Denied"
            case .notDetermined:
                statusString = "Not Determined"
            @unknown default:
                statusString = "Unknown"
            }
            statuses[sensorName(sensor)] = statusString
        }

        DispatchQueue.main.async {
            self.isAvailable = true
            self.authorizationStatuses = statuses
        }
    }

    // MARK: - Authorization Request
    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        guard #available(iOS 14.0, *) else {
            completion(false, NSError(domain: "SensorKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "SensorKit is not supported on this iOS version"]))
            return
        }

        let sensorSet = Set(approvedSensors)
        SRSensorReader.requestAuthorization(sensors: sensorSet) { [weak self] error in
            DispatchQueue.main.async {
                self?.checkAvailabilityAndStatus()
                if let error = error {
                    completion(false, error)
                } else {
                    completion(true, nil)
                }
            }
        }
    }

    // MARK: - Data Fetch Cycle
    func fetchSensorKitData(from startDate: Date = Date().addingTimeInterval(-86400),
                            to endDate: Date = Date()) {
        guard #available(iOS 14.0, *), isAvailable else { return }
        guard !isFetching else { return }

        DispatchQueue.main.async { self.isFetching = true }

        fetchQueue.async { [weak self] in
            guard let self = self else { return }

            let fetchRequest = SRFetchRequest()
            fetchRequest.from = SRAbsoluteTime(startDate.timeIntervalSinceReferenceDate)
            fetchRequest.to = SRAbsoluteTime(endDate.timeIntervalSinceReferenceDate)

            for (sensor, reader) in self.readers {
                if reader.authorizationStatus == .authorized {
                    reader.fetch(fetchRequest)
                }
            }

            DispatchQueue.main.async {
                self.isFetching = false
                self.lastFetchDate = Date()
            }
        }
    }

    // MARK: - SRSensorReaderDelegate Callbacks
    func sensorReader(_ reader: SRSensorReader, fetching fetchRequest: SRFetchRequest, didFetchResult result: SRFetchResult) -> Bool {
        guard let dm = dataManager else { return true }

        let sample = result.sample
        let timestampMs = Int64((result.timestamp.rawValue + Date.timeIntervalBetween1970AndReferenceDate) * 1000)

        switch reader.sensor {
        case .accelerometer:
            if let accelData = sample as? CMRecordedAccelerometerData {
                dm.writeSensorKitAccelerometerRow(timestampMs: timestampMs, x: accelData.acceleration.x, y: accelData.acceleration.y, z: accelData.acceleration.z)
                incrementCount("accelerometer")
            }
        case .rotationRate:
            if let gyroData = sample as? CMRecordedRotationRateData {
                dm.writeSensorKitRotationRateRow(timestampMs: timestampMs, x: gyroData.rotationRate.x, y: gyroData.rotationRate.y, z: gyroData.rotationRate.z)
                incrementCount("rotationRate")
            }
        case .keyboardMetrics:
            if let kbData = sample as? SRKeyboardMetrics {
                let totalWords = kbData.totalWords
                let deleteCount = kbData.totalAlphanumericKeys // proxy metric for typing volume
                let pauseCount = kbData.totalPathPauses
                let typingSpeed = kbData.typingSpeed
                dm.writeSensorKitKeyboardRow(timestampMs: timestampMs, totalWords: totalWords, deleteCount: deleteCount, pauseCount: pauseCount, typingSpeed: typingSpeed)
                incrementCount("keyboardMetrics")
            }
        case .deviceUsage:
            if let usageReport = sample as? SRDeviceUsageReport {
                let duration = usageReport.duration
                let totalUnlocks = usageReport.totalScreenWakes
                let unlockDuration = usageReport.totalUnlockDuration
                let webUsage = usageReport.totalWebUsage
                dm.writeSensorKitDeviceUsageRow(timestampMs: timestampMs, durationSeconds: duration, totalUnlocks: totalUnlocks, unlockDurationSeconds: unlockDuration, webUsageSeconds: webUsage)
                incrementCount("deviceUsage")
            }
        default:
            break
        }

        return true
    }

    func sensorReader(_ reader: SRSensorReader, didCompleteFetch fetchRequest: SRFetchRequest) {
        // Fetch completed for reader
    }

    func sensorReader(_ reader: SRSensorReader, fetchFailedRequest fetchRequest: SRFetchRequest, withError error: Error) {
        print("[SensorKitManager] Fetch failed for \(reader.sensor.rawValue): \(error.localizedDescription)")
    }

    // MARK: - Helpers
    private func incrementCount(_ key: String) {
        DispatchQueue.main.async {
            let current = self.sampleCountsToday[key] ?? 0
            self.sampleCountsToday[key] = current + 1
        }
    }

    private func sensorName(_ sensor: SRSensor) -> String {
        switch sensor {
        case .accelerometer: return "Accelerometer"
        case .rotationRate: return "Rotation Rate"
        case .keyboardMetrics: return "Keyboard Metrics"
        case .deviceUsage: return "Device Usage"
        default: return sensor.rawValue
        }
    }
}
