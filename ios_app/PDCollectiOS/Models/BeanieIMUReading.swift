import Foundation

struct BeanieIMUReading {
    let timestamp: Int64
    let deviceName: String
    let deviceAddress: String
    let axRaw: Int16, ayRaw: Int16, azRaw: Int16
    let gxRaw: Int16, gyRaw: Int16, gzRaw: Int16
    // Converted values
    let axG: Double, ayG: Double, azG: Double
    let accelMagG: Double
    let gxDps: Double, gyDps: Double, gzDps: Double
    let gyroMagDps: Double
    
    var csvRow: String {
        // en_US_POSIX: force "." decimals regardless of device region — see
        // the note in PhysicalActivityEvent.csvRow for why this matters.
        return "\(timestamp),\(deviceName),\(deviceAddress)," +
               "\(axRaw),\(ayRaw),\(azRaw),\(gxRaw),\(gyRaw),\(gzRaw)," +
               String(format: "%.4f,%.4f,%.4f,%.4f,%.2f,%.2f,%.2f,%.2f",
                      locale: Locale(identifier: "en_US_POSIX"),
                      axG, ayG, azG, accelMagG, gxDps, gyDps, gzDps, gyroMagDps) +
               "\n"
    }
}
