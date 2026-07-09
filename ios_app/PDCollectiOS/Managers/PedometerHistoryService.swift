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
///
/// An `actor` rather than a plain class + DispatchQueue: `isSyncing` and the
/// synced-through marker are read/written from several different call sites
/// (app launch, every foreground, every BGTask), and actor isolation makes
/// that safe automatically instead of relying on a manually-managed queue.
actor PedometerHistoryService {

    static let shared = PedometerHistoryService()

    private let pedometer = CMPedometer()
    private let lastSyncKey = "pedometerLastSyncMs"
    private var isSyncing = false

    private init() {}

    nonisolated var isAvailable: Bool { CMPedometer.isStepCountingAvailable() }

    /// Queries one CMPedometer window per completed hour between the last
    /// synced point (or 7 days ago on first run) and now, writes a row for
    /// every hour that had at least one step, then advances the synced-through
    /// marker to the last hour actually completed (not necessarily all the
    /// way to "now" — see the cancellation note below). Cheap to call
    /// repeatedly — a fast no-op once caught up to "now" — so it's safe to
    /// trigger from app launch, every foreground, and every BGTask wake for
    /// maximum coverage.
    func syncHistory(dataManager: DataManager) async {
        guard isAvailable, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

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
        guard !hourStarts.isEmpty else { return }

        // Sequential, not a TaskGroup fan-out: gentler on the motion
        // co-processor than firing dozens of simultaneous queries, and lets
        // Task.isCancelled genuinely stop a BGTask-driven backfill partway
        // through (a TaskGroup would keep every already-started child
        // running regardless of cancellation).
        var lastCompletedHourEnd: Date?
        for hourStart in hourStarts {
            if Task.isCancelled { break }
            let hourEnd = min(calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? now, now)
            if let data = await queryOne(from: hourStart, to: hourEnd), data.numberOfSteps.intValue > 0 {
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
            lastCompletedHourEnd = hourEnd
        }

        // Advance the marker only to the last hour actually queried — if a
        // BGTask expired partway through, the next sync must resume exactly
        // there rather than silently skipping the un-synced remainder.
        if let lastCompletedHourEnd {
            defaults.set(lastCompletedHourEnd.timeIntervalSince1970 * 1000, forKey: lastSyncKey)
        }
    }

    /// One CMPedometer query, awaitable, with a 10s safety net.
    ///
    /// Plain `withCheckedContinuation`, not a TaskGroup-based race: a
    /// TaskGroup keeps every child task alive until it finishes, even a
    /// cancelled one, which would mean a truly hung completion handler still
    /// blocks this function's return — exactly the failure mode a timeout is
    /// meant to prevent. An unstructured `Task` for the timeout has no such
    /// "parent waits for children" constraint, so it can genuinely race
    /// against — and win against — a hung callback.
    private func queryOne(from start: Date, to end: Date) async -> CMPedometerData? {
        await withCheckedContinuation { (continuation: CheckedContinuation<CMPedometerData?, Never>) in
            let lock = NSLock()
            var didResume = false
            func resumeOnce(_ value: CMPedometerData?) {
                lock.lock()
                let alreadyDone = didResume
                didResume = true
                lock.unlock()
                guard !alreadyDone else { return }
                continuation.resume(returning: value)
            }
            pedometer.queryPedometerData(from: start, to: end) { data, _ in
                resumeOnce(data)
            }
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                resumeOnce(nil)
            }
        }
    }
}
