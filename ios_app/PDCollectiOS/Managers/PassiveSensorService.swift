import CoreMotion
import Foundation
import UIKit

/// Passive, continuous sensor collection service analogous to Android's
/// SensorCollectionService. Runs while the app is in the foreground, collecting
/// accelerometer, gyroscope, and magnetometer at ~50 Hz and flushing to disk
/// every 5 seconds (or 250 readings), matching the Android convention.
///
/// Unlike CoreMotionManager (used only during active tests), this service is
/// started on launch and stopped only when the user explicitly disables collection
/// from Settings.
class PassiveSensorService: ObservableObject {

    // MARK: - State

    @Published private(set) var isRunning = false
    @Published private(set) var totalReadingsToday: Int = 0

    // MARK: - Private

    private let motion     = CMMotionManager()
    private let altimeter  = CMAltimeter()
    private let queue      = OperationQueue()
    private var buffer: [SensorReading] = []
    private var flushTimer: Timer?
    private var dataManager: DataManager?

    private let hz: Double       = 50
    private let flushInterval    = 5.0     // seconds
    private let flushThreshold   = 250     // readings

    private var isCollectingActive = false
    private var tokens: [NSObjectProtocol] = []

    // MARK: - Init

    init() {
        queue.name = "com.pdcollect.passive-sensor-queue"
        queue.maxConcurrentOperationCount = 1
    }

    // MARK: - Control

    func start(dataManager: DataManager) {
        guard !isCollectingActive else { return }
        isCollectingActive = true
        self.dataManager = dataManager

        setupObservers()
        startMotionUpdates()

        DispatchQueue.main.async { self.isRunning = true }
    }

    func stop() {
        guard isCollectingActive else { return }
        isCollectingActive = false

        removeObservers()
        stopMotionUpdates()

        DispatchQueue.main.async { self.isRunning = false }
    }

    private func startMotionUpdates() {
        guard motion.isAccelerometerAvailable, motion.isGyroAvailable else { return }
        buffer = []

        motion.deviceMotionUpdateInterval = 1.0 / hz
        motion.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            self.appendReading(data)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.flushTimer?.invalidate()
            self.flushTimer = Timer.scheduledTimer(withTimeInterval: self.flushInterval, repeats: true) { [weak self] _ in
                self?.flush()
            }
        }
    }

    private func stopMotionUpdates() {
        motion.stopDeviceMotionUpdates()
        DispatchQueue.main.async { [weak self] in
            self?.flushTimer?.invalidate()
            self?.flushTimer = nil
        }
        flush()
    }

    private func setupObservers() {
        tokens.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil
            ) { [weak self] _ in
                self?.stopMotionUpdates()
            }
        )
        tokens.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil
            ) { [weak self] _ in
                guard let self, self.isCollectingActive else { return }
                self.startMotionUpdates()
            }
        )
    }

    private func removeObservers() {
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
        tokens = []
    }

    // MARK: - Internal

    private func appendReading(_ data: CMDeviceMotion) {
        let ts = Int64(Date().timeIntervalSince1970 * 1_000_000_000)
        // magnetometer comes via CMDeviceMotion.magneticField (CMCalibratedMagneticField)
        let mag = data.magneticField.field
        let r = SensorReading(
            timestampNs: ts,
            accX: data.userAcceleration.x,
            accY: data.userAcceleration.y,
            accZ: data.userAcceleration.z,
            gyroX: data.rotationRate.x,
            gyroY: data.rotationRate.y,
            gyroZ: data.rotationRate.z
        )
        buffer.append(r)

        _ = mag // magnetometer available — add to extended CSV if schema widens

        if buffer.count >= flushThreshold { flush() }
    }

    private func flush() {
        guard !buffer.isEmpty, let dm = dataManager else { return }
        let toWrite = buffer
        buffer = []
        let count = toWrite.count
        DispatchQueue.global(qos: .utility).async { [weak self] in
            dm.writePassiveSensorReadings(toWrite)
            DispatchQueue.main.async { self?.totalReadingsToday += count }
        }
    }
}
