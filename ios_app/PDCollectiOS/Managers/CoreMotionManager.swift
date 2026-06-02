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
        readings = []
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

    func stopRecording() -> [SensorReading] {
        motion.stopDeviceMotionUpdates()
        DispatchQueue.main.async { self.isRecording = false }
        return readings
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
