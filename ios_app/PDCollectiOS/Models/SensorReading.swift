import Foundation

struct SensorReading {
    let timestampNs: Int64
    let accX: Double
    let accY: Double
    let accZ: Double
    let gyroX: Double
    let gyroY: Double
    let gyroZ: Double

    var csvRow: String {
        String(format: "%lld,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n",
               timestampNs, accX, accY, accZ, gyroX, gyroY, gyroZ)
    }
}
