import Foundation
import CoreMotion

/// Backfills full-day step/walking coverage from CMPedometer, which taps the
/// M-series motion co-processor iOS keeps running at the OS level at all
/// times (the same data source Apple's own Health app uses) — unlike
/// CMMotionManager's raw accelerometer/gyro feed, which iOS only delivers to
/// third-party apps while they're in the foreground.
///
/// This exists because PassiveSensorService (raw sensors, used for gait
/// analysis) can only run while the app is open, so on a phone that's mostly
/// in someone's pocket, passive_sensors.csv ends up covering only the few
/// hours a day the app happened to be foregrounded. CMPedometer's historical
/// query API lets us ask "how many steps happened between X and Y" for any
/// past window, so we can fill in step counts for every hour retroactively —
/// including hours the app was never opened — the moment we get a chance to
/// run (app launch, foreground, or a BGTask wake).
final class PedometerHistoryService {

    static let shared = PedometerHistoryService()

    private let pedometer = CMPedometer()
    private let queue = DispatchQueue(label: "com.pdcollect.pedometer-history", qos: .utility)
    private let lastSyncKey = "pedometerLastSyncMs"
    private var isSyncing = false

    private init() {}

    var isAvailable: Bool { CMPedometer.isStepCountingAvailable() }

    /// Queries one CMPedometer window per completed hour between the last
    /// synced point (or 7 days ago on first run) and now, writes a row for
    /// every hour that had at least one step, then advances the synced-through
    /// marker. Cheap to call repeatedly — a no-op once caught up to "now" —
    /// so it's safe to trigger from app launch, every foreground, and every
    /// BGTask wake for maximum coverage.
    func syncHistory(dataManager: DataManager) {
        guard isAvailable, !isSyncing else { return }
        isSyncing = true

        let now = Date()
        let calendar = Calendar.current
        let defaults = UserDefaults.standard
        let fallbackStart = calendar.date(byAdding: .day, value: -7, to: now) ?? now

        var cursor: Date
        if let storedMs = defaults.object(forKey: lastSyncKey) as? Double {
            cursor = Date(timeIntervalSince1970: storedMs / 1000)
        } else {
            cursor = fallbackStart
        }
        // Never backfill further back than 7 days in one pass — CMPedometer
        // historical queries get slower/less reliable the further back they
        // reach, and a participant should be opening the app at least that
        // often anyway.
        if cursor < fallbackStart { cursor = fallbackStart }

        var hourStarts: [Date] = []
        var hourCursor = calendar.dateInterval(of: .hour, for: cursor)?.start ?? cursor
        while hourCursor < now {
            hourStarts.append(hourCursor)
            guard let next = calendar.date(byAdding: .hour, value: 1, to: hourCursor) else { break }
            hourCursor = next
        }
        guard !hourStarts.isEmpty else {
            isSyncing = false
            return
        }

        queue.async { [weak self] in
            guard let self else { return }
            let group = DispatchGroup()
            for hourStart in hourStarts {
                let hourEnd = min(calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? now, now)
                group.enter()
                self.pedometer.queryPedometerData(from: hourStart, to: hourEnd) { data, error in
                    defer { group.leave() }
                    guard let data, error == nil, data.numberOfSteps.intValue > 0 else { return }
                    let sample = PedometerSample(
                        timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
                        periodStartMs: Int64(hourStart.timeIntervalSince1970 * 1000),
                        periodEndMs: Int64(hourEnd.timeIntervalSince1970 * 1000),
                        steps: data.numberOfSteps.intValue,
                        distanceM: data.distance?.doubleValue,
                        floorsAscended: data.floorsAscended?.intValue,
                        floorsDescended: data.floorsDescended?.intValue,
                        currentPaceSPerM: data.currentPace?.doubleValue,
                        currentCadenceStepsPerS: data.currentCadence?.doubleValue
                    )
                    dataManager.writePedometerSample(sample)
                }
            }
            group.wait()
            defaults.set(now.timeIntervalSince1970 * 1000, forKey: self.lastSyncKey)
            self.isSyncing = false
        }
    }
}
