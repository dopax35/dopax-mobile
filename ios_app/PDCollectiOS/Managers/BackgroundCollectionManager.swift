import BackgroundTasks
import Foundation
import Network

/// Ensures `BGTask.setTaskCompleted(success:)` is called exactly once, even when the
/// normal-completion path and the expiration-handler path race — calling it twice is
/// documented API misuse that can get the app throttled from further BGTask scheduling.
private final class TaskCompletionGuard {
    private let task: BGTask
    private let lock = NSLock()
    private var didComplete = false

    init(task: BGTask) {
        self.task = task
    }

    func complete(success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !didComplete else { return }
        didComplete = true
        task.setTaskCompleted(success: success)
    }
}

/// Schedules and handles BGAppRefreshTask and BGProcessingTask wakeups so the app
/// can continue harvesting HealthKit data and flushing sensor buffers even when
/// backgrounded.
///
/// iOS does not allow true foreground services like Android. BGTask is the closest
/// equivalent: the system wakes the app for ~30 s (refresh) or several minutes
/// (processing, device charging + idle) to perform work.
///
/// Register in PDCollectiOSApp.init() and call scheduleAll() on app launch.
class BackgroundCollectionManager {

    static let shared = BackgroundCollectionManager()

    private init() {}

    // MARK: - Task identifiers (must match Info.plist BGTaskSchedulerPermittedIdentifiers)

    static let refreshTaskId    = "com.pdcollect.ios.bg-refresh"
    static let processingTaskId = "com.pdcollect.ios.bg-processing"

    // MARK: - Dependencies

    private weak var healthKitManager: HealthKitManager?
    private weak var dataManager: DataManager?
    private weak var passiveSensor: PassiveSensorService?
    private weak var sensorKitManager: SensorKitManager?

    func configure(healthKit: HealthKitManager,
                   data: DataManager,
                   sensor: PassiveSensorService,
                   sensorKit: SensorKitManager? = nil) {
        self.healthKitManager = healthKit
        self.dataManager      = data
        self.passiveSensor    = sensor
        self.sensorKitManager = sensorKit
    }

    // MARK: - Registration (call once at app startup before any task fires)

    func registerTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskId,
            using: nil
        ) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            self?.handleRefresh(task: refreshTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.processingTaskId,
            using: nil
        ) { [weak self] task in
            guard let procTask = task as? BGProcessingTask else { return }
            self?.handleProcessing(task: procTask)
        }
    }

    // MARK: - Scheduling

    func scheduleAll() {
        scheduleRefresh()
        scheduleProcessing()
    }

    private func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // ~15 min
        try? BGTaskScheduler.shared.submit(request)
    }

    private func scheduleProcessing() {
        let request = BGProcessingTaskRequest(identifier: Self.processingTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // ~1 hour
        // Always allow network access — the handler checks autoUploadEnabled at execution time
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Handlers

    private func handleRefresh(task: BGAppRefreshTask) {
        scheduleRefresh() // reschedule immediately for next cycle

        // The HealthKit/CoreMotion continuations awaited below aren't cancellation-aware,
        // so op.cancel() in the expiration handler doesn't actually stop them — the Task
        // body keeps running and can call setTaskCompleted a second time after expiration
        // already called it once. Calling setTaskCompleted twice is documented API misuse
        // and can get the app throttled/blocked from further BGTask scheduling, so both
        // paths funnel through this single "complete exactly once" guard.
        let completion = TaskCompletionGuard(task: task)

        let op = Task {
            // Fetch latest HealthKit gait metrics and persist them
            if let hk = healthKitManager, let dm = dataManager {
                let metrics = await hk.fetchGaitMetrics(days: 1)
                if !metrics.isEmpty {
                    let csv = hk.csvString(for: metrics)
                    dm.appendGaitMetrics(csvString: csv)
                }
            }
            // Every opportunistic wake is a chance to backfill step history
            // and activity-type context for hours the app wasn't open — see
            // PedometerHistoryService / MotionActivityHistoryService.
            if let dm = dataManager {
                await PedometerHistoryService.shared.syncHistory(dataManager: dm)
                await MotionActivityHistoryService.shared.syncHistory(dataManager: dm)
            }
            if let sk = sensorKitManager {
                sk.fetchSensorKitData()
            }
            completion.complete(success: true)
        }

        task.expirationHandler = {
            op.cancel()
            completion.complete(success: false)
        }
    }

    private func handleProcessing(task: BGProcessingTask) {
        scheduleProcessing() // reschedule

        let completion = TaskCompletionGuard(task: task)

        let op = Task {
            // Fetch up to 7 days of HealthKit data during a processing window
            if let hk = healthKitManager, let dm = dataManager {
                let metrics = await hk.fetchGaitMetrics(days: 7)
                if !metrics.isEmpty {
                    let csv = hk.csvString(for: metrics)
                    dm.appendGaitMetrics(csvString: csv)
                }
            }
            if let dm = dataManager {
                await PedometerHistoryService.shared.syncHistory(dataManager: dm)
                await MotionActivityHistoryService.shared.syncHistory(dataManager: dm)
            }

            // Auto-upload pending data if enabled. Wi-Fi-preferred, matching
            // Android's existing DataUploadWorker design (UNMETERED attempt
            // first, CONNECTED/cellular fallback only once data has been
            // waiting a while) — see shouldUploadNow(). The manual "Upload
            // Now" button in Settings deliberately does NOT use this gate.
            if UserDefaults.standard.bool(forKey: "autoUploadEnabled"),
               let dm = dataManager {
                await Self.uploadPendingDates(dataManager: dm, requireWifiUnlessStale: true)
            }

            completion.complete(success: true)
        }

        task.expirationHandler = {
            op.cancel()
            completion.complete(success: false)
        }
    }

    // MARK: - Auto Upload

    /// Upload all un-uploaded past dates. Called from the processing handler,
    /// the foreground-triggered check in AppState, and the "Upload Now"
    /// button in Settings.
    ///
    /// - Parameter requireWifiUnlessStale: When true, skips the run entirely
    ///   on an expensive/constrained (cellular) connection unless it's been
    ///   at least 24h since the last successful upload — mirrors Android's
    ///   DataUploadWorker, which tries Wi-Fi (UNMETERED) immediately and only
    ///   falls back to any connection after a delay, rather than spending a
    ///   participant's cellular data on every single automatic backup. Left
    ///   `false` (upload immediately, any network) for the manual button,
    ///   since a participant explicitly tapping "Upload Now" has made a
    ///   deliberate choice that shouldn't be second-guessed.
    static func uploadPendingDates(dataManager dm: DataManager, requireWifiUnlessStale: Bool = false) async {
        if requireWifiUnlessStale, !(await shouldUploadNow()) {
            print("[AutoUpload] Skipped — on cellular and last upload was recent; waiting for Wi-Fi.")
            return
        }

        let todayKey = Date().dateKey
        let dates = dm.listDates()
        let uploader = CloudUploader()
        var uploadedAny = false

        for dateStr in dates {
            // The BGProcessingTask expirationHandler calls op.cancel(), but
            // that only flips a flag — it doesn't stop this loop by itself.
            // Without this check, an upload run that gets cancelled because
            // the system revoked our background time keeps burning that
            // (already-expired) time budget uploading further dates anyway.
            if Task.isCancelled { return }
            if dateStr == todayKey || dm.isUploaded(dateStr) { continue }

            // Claim the upload slot so that a concurrent manual-upload tap or
            // a second BGProcessingTask wakeup cannot race us and send the
            // same date's data twice.  Mirrors Android's UploadState.tryClaimUpload().
            guard dm.tryClaimUpload(dateStr) else {
                print("[AutoUpload] Skipping \(dateStr) — another upload already in progress or complete.")
                continue
            }

            do {
                let zipURL = try dm.zipDate(dateStr)
                try await uploader.upload(
                    zipURL: zipURL,
                    userId: dm.userId,
                    dateStr: dateStr,
                    progressHandler: nil
                )
                try? FileManager.default.removeItem(at: zipURL)
                dm.markUploaded(dateStr)   // also clears the claim marker
                uploadedAny = true
                print("[AutoUpload] Uploaded \(dateStr) ✅")
            } catch {
                dm.clearUploadClaim(dateStr)   // release the lock so a retry can re-claim
                print("[AutoUpload] Failed \(dateStr): \(error.localizedDescription)")
            }
        }


        if uploadedAny {
            UserDefaults.standard.set(Date().timeIntervalSince1970 * 1000, forKey: "lastSuccessfulUploadMs")
        }
    }

    /// True if on Wi-Fi (or otherwise unmetered/unrestricted), or if on
    /// cellular but data has already been waiting 24h+ for a successful
    /// upload (better to spend some cellular data than let research data
    /// sit indefinitely on a phone that rarely sees Wi-Fi).
    private static func shouldUploadNow() async -> Bool {
        let monitor = NWPathMonitor()
        let lock = NSLock()
        var didResume = false
        let path = await withCheckedContinuation { (continuation: CheckedContinuation<NWPath, Never>) in
            monitor.pathUpdateHandler = { path in
                lock.lock()
                let alreadyDone = didResume
                didResume = true
                lock.unlock()
                guard !alreadyDone else { return }
                continuation.resume(returning: path)
            }
            monitor.start(queue: DispatchQueue.global(qos: .utility))
        }
        monitor.cancel()

        if !path.isExpensive && !path.isConstrained { return true }

        guard let lastMs = UserDefaults.standard.object(forKey: "lastSuccessfulUploadMs") as? Double else {
            return true // never uploaded before — don't block indefinitely waiting for Wi-Fi
        }
        let hoursSinceLastUpload = (Date().timeIntervalSince1970 * 1000 - lastMs) / 3_600_000
        return hoursSinceLastUpload >= 24
    }
}
