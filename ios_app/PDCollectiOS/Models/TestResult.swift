import Foundation

struct TestResult {
    let timestamp: Date
    let testType: TestType
    let part: String
    let score: Double
    let durationMs: Int
    let errors: Int
    let details: String

    enum TestType: String {
        case trailMaking   = "trail_making"
        case fingerTapping = "finger_tapping"
        case handTurning   = "hand_turning"
        case spiralTracing = "spiral_tracing"
        case legAgility    = "leg_agility"
    }

    var csvRow: String {
        let ts = ISO8601DateFormatter().string(from: timestamp)
        let safeDetails = details.replacingOccurrences(of: "\"", with: "\"\"")
        return "\(ts),\(testType.rawValue),\(part),\(String(format: "%.3f", score)),\(durationMs),\(errors),\"\(safeDetails)\"\n"
    }
}
