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
    
    var csvRow: String {
        let bat = batteryPct.map(String.init) ?? ""
        return "\(timestamp),\(deviceName),\(deviceAddress),\(profileName)," +
               String(format: "%.2f,%.2f,%.2f,%.4f", innerC, outerC, tskinC, heatFluxCalPerSec) +
               ",\(bat)\n"
    }
}
