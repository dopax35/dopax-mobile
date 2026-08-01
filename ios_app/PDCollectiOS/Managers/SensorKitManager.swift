// TestFlight Build: SensorKit Disabled
#define DISABLE_SENSORKIT 1
import Foundation
import Combine

#if canImport(SensorKit) && !DISABLE_SENSORKIT
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

            let statusStr: String
            switch reader.authorizationStatus {
            case .authorized:
                statusStr = "Authorized"
            case .denied:
                statusStr = "Denied"
            case .notDetermined:
                statusStr = "Not Determined"
            @unknown default:
                statusStr = "Unknown"
            }
            statuses[sensor.rawValue] = statusStr
        }

        DispatchQueue.main.async {
            self.authorizationStatuses = statuses
            self.isAvailable = true
        }
    }

    // MARK: - Authorization Request
    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        guard #available(iOS 14.0, *), isAvailable else {
            completion(false, NSError(domain: "SensorKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "SensorKit is not supported on this iOS version"]))
            return
        }

        let sensorsToRequest = Set(approvedSensors)
        SRSensorReader.requestAuthorization(sensors: sensorsToRequest) { [weak self] error in
            DispatchQueue.main.async {
                self?.checkAvailabilityAndStatus()
                completion(error == nil, error)
            }
        }
    }

    // MARK: - Data Fetching
    func fetchSensorKitData(from startDate: Date = Date().addingTimeInterval(-86400),
                             to endDate: Date = Date()) {
        guard #available(iOS 14.0, *), isAvailable else { return }

        DispatchQueue.main.async { self.isFetching = true }

        let fetchGroup = DispatchGroup()

        for sensor in approvedSensors {
            guard let reader = readers[sensor],
                  reader.authorizationStatus == .authorized else {
                continue
            }

            fetchGroup.enter()
            let request = SRFetchRequest()
            request.from = SRAbsoluteTime(from: startDate)
            request.to = SRAbsoluteTime(from: endDate)

            reader.fetch(request)
        }

        fetchGroup.notify(queue: .main) {
            self.isFetching = false
            self.lastFetchDate = Date()
        }
    }

    // MARK: - SRSensorReaderDelegate
    func sensorReader(_ reader: SRSensorReader,
                      fetching request: SRFetchRequest,
                      didFetch result: SRFetchResult) -> Bool {
        guard let dm = dataManager else { return true }

        let timestampMs = Int64(result.timestamp.date.timeIntervalSince1970 * 1000)
        let sample = result.sample

        switch reader.sensor {
        case .accelerometer:
            if let accelData = sample as? CRAcceleration {
                dm.writeSensorKitAccelerometerRow(timestampMs: timestampMs, x: accelData.acceleration.x, y: accelData.acceleration.y, z: accelData.acceleration.z)
                incrementCount("accelerometer")
            }
        case .rotationRate:
            if let gyroData = sample as? CRRotationRate {
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
}

#else

// MARK: - TestFlight Stub (Compiled when DISABLE_SENSORKIT is defined or SensorKit framework is omitted)
class SensorKitManager: NSObject, ObservableObject {
    @Published private(set) var isAvailable: Bool = false
    @Published private(set) var isFetching: Bool = false
    @Published private(set) var lastFetchDate: Date? = nil
    @Published private(set) var authorizationStatuses: [String: String] = [:]
    @Published private(set) var sampleCountsToday: [String: Int] = [
        "accelerometer": 0,
        "rotationRate": 0,
        "keyboardMetrics": 0,
        "deviceUsage": 0
    ]

    override init() {
        super.init()
    }

    func configure(dataManager: DataManager) {}
    func checkAvailabilityAndStatus() {}
    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        completion(false, nil)
    }
    func fetchSensorKitData(from startDate: Date = Date().addingTimeInterval(-86400), to endDate: Date = Date()) {}
}

#endif
