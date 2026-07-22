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
        // Routed through `queue` for the same reason as in `flush()` — avoids racing a
        // still-in-flight `appendReading` call from a motion callback delivered just
        // before this restart.
        queue.addOperation { [weak self] in self?.buffer = [] }

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
        // CMDeviceMotion.timestamp is relative to device boot (systemUptime),
        // not wall-clock — Date() was used here before, which stamps each
        // sample at CALLBACK-DELIVERY time rather than true capture time.
        // Those match closely when callbacks arrive smoothly, but whenever
        // the OperationQueue falls behind and then drains a backlog in a
        // tight loop (e.g. right after the app resumes, or under brief CPU
        // contention), every queued sample fires its callback within a
        // fraction of a millisecond of the others — confirmed in real
        // participant data as bursts of hundreds to thousands of rows all
        // landing within the same second, instead of their true ~20ms-apart
        // capture times. Converting the boot-relative timestamp to
        // wall-clock fixes this: every row keeps its real, evenly-spaced
        // capture time no matter how bursty delivery was.
        let bootDate = Date(timeIntervalSinceNow: -ProcessInfo.processInfo.systemUptime)
        let sampleDate = bootDate.addingTimeInterval(data.timestamp)
        let ts = Int64(sampleDate.timeIntervalSince1970 * 1_000_000_000)
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

    /// `appendReading` runs on `queue` (CoreMotion's delivery queue) while `flush` was
    /// previously called from the main-thread timer and from background/foreground
    /// notification handlers — mutating `buffer` from two threads with no synchronization
    /// at sustained 50Hz is a data race that can corrupt the array and crash. Funnelling
    /// the swap itself through `queue` serializes it with every `appendReading` call; the
    /// actual (slower) disk write stays off `queue` so it doesn't stall motion delivery.
    private func flush() {
        queue.addOperation { [weak self] in
            guard let self, !self.buffer.isEmpty, let dm = self.dataManager else { return }
            let toWrite = self.buffer
            self.buffer = []
            let count = toWrite.count
            DispatchQueue.global(qos: .utility).async {
                dm.writePassiveSensorReadings(toWrite)
                DispatchQueue.main.async { self.totalReadingsToday += count }
            }
        }
    }
}
