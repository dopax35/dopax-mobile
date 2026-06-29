import Foundation

/// A user-reported physical activity event.
/// Matches Android's physical_activity.csv format.
struct PhysicalActivityEvent {
    let timestampMs: Int64     // when the event was recorded
    let activityType: String   // "Running", "Bike", "Other"
    let timeOfDayMs: Int64     // user-selected time of activity

    var csvRow: String {
        "\(timestampMs),\(activityType),\(timeOfDayMs)\n"
    }

    /// Available activity types (matches Android's Constants.PHYSICAL_ACTIVITY_TYPES)
    static let activityTypes = ["Running", "Bike", "Other"]
}
