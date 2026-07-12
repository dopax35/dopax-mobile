import Foundation
import CoreMotion

/// Backfills all-day activity-type context (walking / running / stationary /
/// automotive / cycling, each with a confidence level) from
/// CMMotionActivityManager. Like CMPedometer, this taps a signal the
/// M-series motion co-processor classifies continuously at the OS level,
/// independent of whether this app is open — so it fills in real movement
/// *context* for the same foreground-only hours PassiveSensorService can't
/// cover. Complements PedometerHistoryService's step counts with what kind
/// of movement was happening, not just how much.
///
/// Simpler than PedometerHistoryService: CMMotionActivityManager's query
/// returns a list of discrete "activity changed to X at time Y" events for
/// an entire open date range in one call, so there's no need to chunk the
/// range into hourly windows — one query covers everything since the last
/// sync.
actor MotionActivityHistoryService {

    static let shared = MotionActivityHistoryService()

    private let activityManager = CMMotionActivityManager()
    private let lastSyncKey = "motionActivityLastSyncMs"
    private var isSyncing = false

    private init() {}

    nonisolated var isAvailable: Bool { CMMotionActivityManager.isActivityAvailable() }

    /// Fetches every activity-classification change since the last sync (or
    /// 7 days ago on first run) and writes one row per change, then advances
    /// the synced-through marker. Cheap to call repeatedly — a fast no-op
    /// once caught up — so it's safe to trigger from app launch, every
    /// foreground, and every BGTask wake, same as PedometerHistoryService.
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
        if cursor < fallbackStart { cursor = fallbackStart }
        guard cursor < now else { return }

        guard let activities = await queryActivities(from: cursor, to: now) else { return }

        var lastProcessedStart: Date?
        var completedFully = true
        for activity in activities {
            if Task.isCancelled { completedFully = false; break }
            // Skip entries with no signal at all rather than writing an
            // empty-flags row — Apple documents brief "unknown, low
            // confidence" transitions as possible/expected noise.
            guard activity.stationary || activity.walking || activity.running
                || activity.automotive || activity.cycling || activity.unknown else {
                lastProcessedStart = activity.startDate
                continue
            }
            let sample = MotionActivitySample(
                timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
                activityStartMs: Int64(activity.startDate.timeIntervalSince1970 * 1000),
                confidence: confidenceString(activity.confidence),
                stationary: activity.stationary,
                walking: activity.walking,
                running: activity.running,
                automotive: activity.automotive,
                cycling: activity.cycling,
                unknown: activity.unknown
            )
            dataManager.writeMotionActivitySample(sample)
            lastProcessedStart = activity.startDate
        }

        // The query itself already fetched the entire cursor...now range, so
        // if we made it through the write loop uninterrupted, the marker can
        // safely advance all the way to "now". If cancelled partway through
        // writing, advance only to the last row actually written — the next
        // sync re-fetches and re-writes the small remainder, which is safe.
        if completedFully {
            defaults.set(now.timeIntervalSince1970 * 1000, forKey: lastSyncKey)
        } else if let lastProcessedStart {
            defaults.set(lastProcessedStart.timeIntervalSince1970 * 1000, forKey: lastSyncKey)
        }
    }

    private func confidenceString(_ c: CMMotionActivityConfidence) -> String {
        switch c {
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        @unknown default: return "unknown"
        }
    }

    /// One CMMotionActivityManager historical query, awaitable, with a 15s
    /// safety net (longer than PedometerHistoryService's 10s — this call can
    /// cover a full 7-day range in one shot rather than one hour at a time).
    /// Same unstructured-Task-race pattern as PedometerHistoryService.queryOne,
    /// for the same reason: a TaskGroup would block this function's return on
    /// every child finishing, including a hung one, defeating the timeout.
    private func queryActivities(from start: Date, to end: Date) async -> [CMMotionActivity]? {
        await withCheckedContinuation { (continuation: CheckedContinuation<[CMMotionActivity]?, Never>) in
            let lock = NSLock()
            var didResume = false
            func resumeOnce(_ value: [CMMotionActivity]?) {
                lock.lock()
                let alreadyDone = didResume
                didResume = true
                lock.unlock()
                guard !alreadyDone else { return }
                continuation.resume(returning: value)
            }
            activityManager.queryActivityStarting(from: start, to: end, to: .main) { activities, _ in
                resumeOnce(activities)
            }
            Task {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                resumeOnce(nil)
            }
        }
    }
}
