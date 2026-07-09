import Foundation

/// A sleep session imported from a connected health source (Apple Health,
/// which in turn surfaces Garmin Connect / Oura / AutoSleep / etc. — whatever
/// the user has syncing into it). Matches Android's sleep.csv format exactly.
struct SleepEvent {
    let timestampMs: Int64          // when the import happened
    var source: String = "HealthKit" // "HealthKit" | "HealthConnect"
    /// The specific app that actually recorded the night, e.g. "Garmin
    /// Connect" or "Apple Watch" — nil if the source doesn't expose one.
    var provider: String?
    let sleepStartMs: Int64
    let sleepEndMs: Int64
    var timeInBedMin: Double
    var totalSleepMin: Double
    var lightMin: Double = 0
    var deepMin: Double = 0
    var remMin: Double = 0
    var awakeMin: Double = 0
    var unspecifiedMin: Double = 0
    // Stable per-source identifier used only to skip re-importing the same
    // night on a later import — never written to the CSV. nil/empty means
    // the source didn't supply one, which ImportedActivityStore treats as
    // "can't dedupe this one, always import" rather than silently dropping it.
    var externalId: String?

    var csvRow: String {
        // en_US_POSIX forces a "." decimal separator regardless of the
        // device's region — see the same note in PhysicalActivityEvent.csvRow.
        let posix = Locale(identifier: "en_US_POSIX")
        func fmt(_ v: Double) -> String { String(format: "%.1f", locale: posix, v) }
        // Commas can't appear in a provider app name in practice, but guard
        // anyway rather than risk a silently-shifted CSV row.
        let providerField = (provider ?? "").replacingOccurrences(of: ",", with: ";")
        return "\(timestampMs),\(source),\(providerField),\(sleepStartMs),\(sleepEndMs),"
            + "\(fmt(timeInBedMin)),\(fmt(totalSleepMin)),\(fmt(lightMin)),\(fmt(deepMin)),"
            + "\(fmt(remMin)),\(fmt(awakeMin)),\(fmt(unspecifiedMin))\n"
    }
}
