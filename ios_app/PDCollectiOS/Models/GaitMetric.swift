import Foundation

struct GaitMetric: Identifiable {
    let id = UUID()
    let date: Date
    let walkingSpeed: Double?              // m/s
    let stepLength: Double?                // meters
    let walkingSteadiness: Double?         // 0.0–1.0
    let doubleSupportPercentage: Double?   // percent
    let asymmetryPercentage: Double?       // percent
    let heartRate: Double?                 // bpm
    let hrvSDNN: Double?                   // ms
}

struct GaitSummary {
    let metrics: [GaitMetric]

    var latestNonNil: GaitMetric? { metrics.last }

    var averageWalkingSpeed: Double? {
        average(metrics.compactMap(\.walkingSpeed))
    }
    var averageStepLength: Double? {
        average(metrics.compactMap(\.stepLength))
    }
    var latestSteadiness: Double? {
        metrics.compactMap(\.walkingSteadiness).last
    }
    var averageHeartRate: Double? {
        average(metrics.compactMap(\.heartRate))
    }

    private func average(_ vals: [Double]) -> Double? {
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }
}
