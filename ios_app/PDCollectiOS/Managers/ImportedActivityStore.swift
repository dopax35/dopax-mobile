import Foundation

/// Tracks which externally-imported workouts (Apple Health / Strava) have
/// already been written to physical_activity.csv, so re-importing the same
/// rolling look-back window — e.g. tapping "Import" again a few days later,
/// while the fetch window still overlaps the previous import — doesn't
/// create duplicate rows for the same workout.
///
/// Keyed by "source:externalId" rather than just the raw ID, since each
/// source's IDs only make sense within that source's own ID space (a
/// HealthKit UUID and a Strava numeric activity ID could theoretically
/// collide as raw strings). Matches Android's ImportedActivityStore.
///
/// Deliberately NOT scoped to the current profile / cleared on
/// Reset & Withdraw: a stale ID left behind from a previous participant on a
/// reused device is harmless (a new participant's own Strava/HealthKit
/// account IDs are globally unique and will never collide with an old one),
/// so there's no correctness reason to wire this into that flow.
enum ImportedActivityStore {
    private static let defaultsKey = "imported_activity_ids"

    // Soft cap so this can't grow unbounded across years of daily imports.
    // Generously larger than any realistic number of workouts imported
    // across the fetch window's lifetime; trimming drops the oldest entries
    // first since they're stored in insertion order.
    private static let maxRemembered = 2000

    static func isAlreadyImported(source: String, externalId: String) -> Bool {
        guard !externalId.isEmpty else { return false }
        return ids().contains(key(source, externalId))
    }

    static func markImported(source: String, externalId: String) {
        guard !externalId.isEmpty else { return }
        var current = ids()
        let k = key(source, externalId)
        guard !current.contains(k) else { return }
        current.append(k)
        if current.count > maxRemembered {
            current = Array(current.suffix(maxRemembered))
        }
        UserDefaults.standard.set(current, forKey: defaultsKey)
    }

    private static func ids() -> [String] {
        UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
    }

    private static func key(_ source: String, _ externalId: String) -> String {
        "\(source):\(externalId)"
    }
}
