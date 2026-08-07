import Foundation
import Combine

#if canImport(SensorKit) && !DISABLE_SENSORKIT
import SensorKit
import CoreMotion
#endif

/// Manages SensorKit reader access for Parkinson's Disease research.
class SensorKitManager: NSObject, ObservableObject {

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

    private weak var dataManager: DataManager?

    #if canImport(SensorKit) && !DISABLE_SENSORKIT
    private var readers: [SRSensor: SRSensorReader] = [:]
    private let fetchQueue = DispatchQueue(label: "com.pdcollect.sensorkit-queue", qos: .utility)
    private let approvedSensors: [SRSensor] = [
        .accelerometer,
        .rotationRate,
        .keyboardMetrics,
        .deviceUsageReport
    ]
    #endif

    override init() {
        super.init()
        checkAvailabilityAndStatus()
    }

    func configure(dataManager: DataManager) {
        self.dataManager = dataManager
        checkAvailabilityAndStatus()
    }

    func checkAvailabilityAndStatus() {
        #if canImport(SensorKit) && !DISABLE_SENSORKIT
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
        #else
        DispatchQueue.main.async {
            self.isAvailable = false
        }
        #endif
    }

    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        #if canImport(SensorKit) && !DISABLE_SENSORKIT
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
        #else
        completion(false, nil)
        #endif
    }

    func fetchSensorKitData(from startDate: Date = Date().addingTimeInterval(-86400),
                             to endDate: Date = Date()) {
        #if canImport(SensorKit) && !DISABLE_SENSORKIT
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
            request.from = SRAbsoluteTime(startDate.timeIntervalSinceReferenceDate)
            request.to = SRAbsoluteTime(endDate.timeIntervalSinceReferenceDate)

            reader.fetch(request)
        }

        fetchGroup.notify(queue: .main) {
            self.isFetching = false
            self.lastFetchDate = Date()
        }
        #endif
    }
}

#if canImport(SensorKit) && !DISABLE_SENSORKIT
extension SensorKitManager: SRSensorReaderDelegate {
    func sensorReader(_ reader: SRSensorReader,
                      fetching request: SRFetchRequest,
                      didFetchResult result: SRFetchResult<AnyObject>) -> Bool {
        guard let dm = dataManager else { return true }

        let date = Date(timeIntervalSinceReferenceDate: result.timestamp)
        let timestampMs = Int64(date.timeIntervalSince1970 * 1000)
        let sample = result.sample

        switch reader.sensor {
        case .accelerometer:
            if let accelData = sample as? CMAccelerometerData {
                dm.writeSensorKitAccelerometerRow(timestampMs: timestampMs, x: accelData.acceleration.x, y: accelData.acceleration.y, z: accelData.acceleration.z)
                incrementCount("accelerometer")
            }
        case .rotationRate:
            if let gyroData = sample as? CMRotationRateData {
                dm.writeSensorKitRotationRateRow(timestampMs: timestampMs, x: gyroData.rotationRate.x, y: gyroData.rotationRate.y, z: gyroData.rotationRate.z)
                incrementCount("rotationRate")
            }
        case .keyboardMetrics:
            if let kbData = sample as? SRKeyboardMetrics {
                let totalWords = kbData.totalWords
                let deleteCount = (kbData.value(forKey: "totalAlphanumericKeys") as? Int) ?? (kbData.value(forKey: "totalDeletes") as? Int) ?? 0
                let pauseCount = (kbData.value(forKey: "totalPathPauses") as? Int) ?? (kbData.value(forKey: "totalPauses") as? Int) ?? 0
                let typingSpeed = kbData.typingSpeed
                dm.writeSensorKitKeyboardRow(timestampMs: timestampMs, totalWords: totalWords, deleteCount: deleteCount, pauseCount: pauseCount, typingSpeed: typingSpeed)
                incrementCount("keyboardMetrics")
            }
        case .deviceUsageReport:
            if let usageReport = sample as? SRDeviceUsageReport {
                let duration = usageReport.duration
                let totalUnlocks = usageReport.totalScreenWakes
                let unlockDuration = usageReport.totalUnlockDuration
                let webUsage = (usageReport.value(forKey: "totalWebUsage") as? Double) ?? 0.0
                dm.writeSensorKitDeviceUsageRow(timestampMs: timestampMs, durationSeconds: duration, totalUnlocks: totalUnlocks, unlockDurationSeconds: unlockDuration, webUsageSeconds: webUsage)
                incrementCount("deviceUsage")
            }
        default:
            break
        }

        return true
    }

    func sensorReader(_ reader: SRSensorReader, didCompleteFetch fetchRequest: SRFetchRequest) {}

    func sensorReader(_ reader: SRSensorReader, fetchFailedRequest fetchRequest: SRFetchRequest, withError error: Error) {
        print("[SensorKitManager] Fetch failed for \(reader.sensor.rawValue): \(error.localizedDescription)")
    }

    private func incrementCount(_ key: String) {
        DispatchQueue.main.async {
            let current = self.sampleCountsToday[key] ?? 0
            self.sampleCountsToday[key] = current + 1
        }
    }
}
#endif
