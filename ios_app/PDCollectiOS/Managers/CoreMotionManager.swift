import CoreMotion
import Foundation

class CoreMotionManager: ObservableObject {
    private let motion = CMMotionManager()
    private let queue = OperationQueue()
    private(set) var readings: [SensorReading] = []
    @Published var isRecording = false

    // Latest raw values for live display during tests
    @Published var latestGyroZ: Double = 0
    @Published var latestAccMagnitude: Double = 0

    private let hz: Double = 100

    var isAvailable: Bool { motion.isAccelerometerAvailable && motion.isGyroAvailable }

    func startRecording() {
        guard isAvailable, !motion.isDeviceMotionActive else { return }
        // Routed through `queue` (see stopRecording()'s comment) so this reset can't race
        // an append still in flight from a callback delivered just before this restart.
        queue.addOperation { [weak self] in self?.readings = [] }
        motion.deviceMotionUpdateInterval = 1.0 / hz
        motion.startDeviceMotionUpdates(to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            let ts = Int64(data.timestamp * 1_000_000_000)
            let r = SensorReading(
                timestampNs: ts,
                accX: data.userAcceleration.x,
                accY: data.userAcceleration.y,
                accZ: data.userAcceleration.z,
                gyroX: data.rotationRate.x,
                gyroY: data.rotationRate.y,
                gyroZ: data.rotationRate.z
            )
            self.readings.append(r)
            DispatchQueue.main.async {
                self.latestGyroZ = data.rotationRate.z
                let a = data.userAcceleration
                self.latestAccMagnitude = sqrt(a.x*a.x + a.y*a.y + a.z*a.z)
            }
        }
        DispatchQueue.main.async { self.isRecording = true }
    }

    /// Like startRecording but also fires `onSample` on each sensor update
    /// so callers can write CSV rows in real time (matches Android SENSOR_DELAY_FASTEST streaming).
    func startStreaming(onSample: @escaping (SensorReading) -> Void) {
        guard isAvailable, !motion.isDeviceMotionActive else { return }
        queue.addOperation { [weak self] in self?.readings = [] }
        motion.deviceMotionUpdateInterval = 1.0 / hz
        motion.startDeviceMotionUpdates(to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            let ts = Int64(data.timestamp * 1_000_000_000)
            let r = SensorReading(
                timestampNs: ts,
                accX: data.userAcceleration.x,
                accY: data.userAcceleration.y,
                accZ: data.userAcceleration.z,
                gyroX: data.rotationRate.x,
                gyroY: data.rotationRate.y,
                gyroZ: data.rotationRate.z
            )
            self.readings.append(r)
            onSample(r)
            DispatchQueue.main.async {
                self.latestGyroZ = data.rotationRate.z
                let a = data.userAcceleration
                self.latestAccMagnitude = sqrt(a.x*a.x + a.y*a.y + a.z*a.z)
            }
        }
        DispatchQueue.main.async { self.isRecording = true }
    }


    /// `readings.append(r)` happens on `queue` (CoreMotion's delivery queue) at up to
    /// 100Hz, while this used to be called straight from the main thread with no
    /// synchronization — `motion.stopDeviceMotionUpdates()` stops *future* callbacks but
    /// doesn't guarantee one already dispatched to `queue` isn't still about to run,
    /// so reading `readings` directly here was a data race (crash risk / truncated data)
    /// against an in-flight append. Waiting on a final no-op operation drains `queue` of
    /// anything already enqueued before reading the final array.
    func stopRecording() -> [SensorReading] {
        motion.stopDeviceMotionUpdates()
        DispatchQueue.main.async { self.isRecording = false }
        var result: [SensorReading] = []
        let drain = BlockOperation { [weak self] in result = self?.readings ?? [] }
        queue.addOperations([drain], waitUntilFinished: true)
        return result
    }

    // Count zero-crossings in gyroZ to quantify pronation/supination cycles
    func countRotationCycles(in data: [SensorReading], threshold: Double = 0.5) -> Int {
        let gyroZ = data.map(\.gyroZ)
        var crossings = 0
        var wasPositive: Bool? = nil
        for v in gyroZ {
            guard abs(v) > threshold else { continue }
            let positive = v > 0
            if let prev = wasPositive, prev != positive { crossings += 1 }
            wasPositive = positive
        }
        return crossings / 2 // full cycles = crossings / 2
    }
}
