import Foundation

/// One hour-bucket of step/walking data backfilled from CMPedometer — the
/// always-on M-series motion co-processor iOS tracks around the clock,
/// independent of whether this app is open or foregrounded. Supplements
/// passive_sensors.csv, which on iOS only covers hours the app was actually
/// in the foreground (see PassiveSensorService). Matches Android's
/// PHYSICAL_ACTIVITY-style locale-safe number formatting; no Android
/// equivalent file exists because Android already gets all-day coverage via
/// its foreground Service, so there's nothing to keep in parity here.
struct PedometerSample {
    let timestampMs: Int64        // when this row was synced (not when the steps happened)
    let periodStartMs: Int64
    let periodEndMs: Int64
    let steps: Int
    var distanceM: Double?
    var floorsAscended: Int?
    var floorsDescended: Int?
    var currentPaceSPerM: Double?
    var currentCadenceStepsPerS: Double?

    var csvRow: String {
        // en_US_POSIX forces a "." decimal separator regardless of the
        // device's region — see the same note in PhysicalActivityEvent.csvRow.
        let posix = Locale(identifier: "en_US_POSIX")
        func fmt(_ v: Double?) -> String {
            guard let v else { return "" }
            return String(format: "%.2f", locale: posix, v)
        }
        func intOrBlank(_ v: Int?) -> String { v.map(String.init) ?? "" }
        return "\(timestampMs),\(periodStartMs),\(periodEndMs),\(steps),"
            + "\(fmt(distanceM)),\(intOrBlank(floorsAscended)),\(intOrBlank(floorsDescended)),"
            + "\(fmt(currentPaceSPerM)),\(fmt(currentCadenceStepsPerS))\n"
    }
}
