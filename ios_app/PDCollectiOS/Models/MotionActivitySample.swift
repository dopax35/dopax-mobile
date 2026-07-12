import Foundation

/// One activity-type classification sample backfilled from
/// CMMotionActivityManager — like PedometerSample, sourced from the always-on
/// motion co-processor iOS tracks regardless of whether this app is open.
/// Multiple flags can be true at once (Apple's own model allows this during
/// ambiguous transitions, e.g. walking+automotive uncertainty), so each
/// activity type is its own boolean column rather than a single category.
struct MotionActivitySample {
    let timestampMs: Int64        // when this row was synced/written
    let activityStartMs: Int64    // when this classification began (CMMotionActivity.startDate)
    let confidence: String        // "low" | "medium" | "high"
    let stationary: Bool
    let walking: Bool
    let running: Bool
    let automotive: Bool
    let cycling: Bool
    let unknown: Bool

    var csvRow: String {
        "\(timestampMs),\(activityStartMs),\(confidence),\(stationary),\(walking),\(running),\(automotive),\(cycling),\(unknown)\n"
    }
}
