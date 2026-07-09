import Foundation

struct BeanieTemperatureReading {
    let timestamp: Int64
    let deviceName: String
    let deviceAddress: String
    let profileName: String
    let innerC: Double
    let outerC: Double
    let tskinC: Double
    let heatFluxCalPerSec: Double
    let batteryPct: Int?
    
    // Inference outputs (populated when Beanie activity model is running)
    var activityLabel: String?
    var activityConfidence: Double?
    
    var csvRow: String {
        // en_US_POSIX: force "." decimals regardless of device region — see
        // the note in PhysicalActivityEvent.csvRow for why this matters.
        let posix = Locale(identifier: "en_US_POSIX")
        let bat = batteryPct.map(String.init) ?? ""
        let act = activityLabel ?? ""
        let conf = activityConfidence.map { String(format: "%.2f", locale: posix, $0) } ?? ""
        return "\(timestamp),\(deviceName),\(deviceAddress),\(profileName)," +
               String(format: "%.2f,%.2f,%.2f,%.4f", locale: posix, innerC, outerC, tskinC, heatFluxCalPerSec) +
               ",\(bat),\(act),\(conf)\n"
    }
}
