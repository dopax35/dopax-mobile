import Foundation

struct HeartRateReading {
    let timestamp: Int64       // milliseconds since epoch
    let bpm: Int
    let rrIntervals: [Int]     // RR intervals in ms
    let deviceAddress: String  // CBPeripheral UUID string
    let deviceName: String
    
    var csvRow: String {
        let rrStr = rrIntervals.map(String.init).joined(separator: "|")
        return "\(timestamp),\(bpm),\(rrStr),\(deviceAddress),\(deviceName)\n"
    }
}
