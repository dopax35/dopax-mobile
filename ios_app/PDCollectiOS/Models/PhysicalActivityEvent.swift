import Foundation

/// A physical activity event — either manually logged or imported from a
/// connected fitness source. Matches Android's physical_activity.csv format.
struct PhysicalActivityEvent {
    let timestampMs: Int64        // when the event was recorded
    let activityType: String      // "Running", "Bike", "Swimming", "Weight Training", "Pilates", "Other"
    let timeOfDayMs: Int64        // user-selected (or workout start) time
    var source: String = "Manual" // "Manual" | "HealthKit" | "Strava"
    var durationMin: Double?      // nil for plain manual entries with no duration
    var calories: Double?
    var avgHeartRate: Double?
    // Stable per-source identifier (HealthKit workout UUID / Strava
    // activity id) used only to skip re-importing the same workout on a
    // later import — never written to the CSV. nil/empty means the source
    // didn't supply one, which ImportedActivityStore treats as "can't
    // dedupe this one, always import" rather than silently dropping it.
    var externalId: String?

    init(timestampMs: Int64, activityType: String, timeOfDayMs: Int64,
         source: String = "Manual", durationMin: Double? = nil,
         calories: Double? = nil, avgHeartRate: Double? = nil,
         externalId: String? = nil) {
        self.timestampMs = timestampMs
        self.activityType = activityType
        self.timeOfDayMs = timeOfDayMs
        self.source = source
        self.durationMin = durationMin
        self.calories = calories
        self.avgHeartRate = avgHeartRate
        self.externalId = externalId
    }

    var csvRow: String {
        // en_US_POSIX forces a "." decimal separator regardless of the
        // device's region — without it, String(format:) uses the current
        // locale, so a comma-decimal region (much of Europe) would write
        // e.g. "45,3" here and silently split this CSV row into an extra
        // column. Android's equivalent code already passes Locale.US to
        // every String.format call for the same reason.
        let posix = Locale(identifier: "en_US_POSIX")
        let dur = durationMin.map { String(format: "%.1f", locale: posix, $0) } ?? ""
        let cal = calories.map { String(format: "%.0f", locale: posix, $0) } ?? ""
        let hr  = avgHeartRate.map { String(format: "%.0f", locale: posix, $0) } ?? ""
        return "\(timestampMs),\(activityType),\(timeOfDayMs),\(source),\(dur),\(cal),\(hr)\n"
    }

    /// Available activity types (matches Android's Constants.PHYSICAL_ACTIVITY_TYPES)
    static let activityTypes = ["Running", "Bike", "Swimming", "Weight Training", "Pilates", "Other"]

    /// Maps a free-text workout name/type (from HealthKit or Strava) onto the
    /// app's fixed activity type list, defaulting to "Other" when unrecognized.
    static func mapExternalType(_ raw: String) -> String {
        let s = raw.lowercased()
        if s.contains("run") { return "Running" }
        if s.contains("cycl") || s.contains("bike") || s.contains("ride") { return "Bike" }
        if s.contains("swim") { return "Swimming" }
        // "workout" matches Strava's generic strength-training activity type
        // name, so this stays consistent with Android's mapStravaType (which
        // treats the same Strava type string as Weight Training).
        if s.contains("strength") || s.contains("weight") || s.contains("workout") { return "Weight Training" }
        if s.contains("yoga") || s.contains("pilates") || s.contains("flexibility") || s.contains("cooldown") { return "Pilates" }
        return "Other"
    }
}
