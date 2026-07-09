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
        // en_US_POSIX: force "." decimals regardless of device region — see
        // the note in PhysicalActivityEvent.csvRow for why this matters.
        String(format: "%lld,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n",
               locale: Locale(identifier: "en_US_POSIX"),
               timestampNs, accX, accY, accZ, gyroX, gyroY, gyroZ)
    }
}
