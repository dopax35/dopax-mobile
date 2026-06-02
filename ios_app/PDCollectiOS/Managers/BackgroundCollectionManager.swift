import BackgroundTasks
import Foundation

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

    // MARK: - Task identifiers (must match Info.plist BGTaskSchedulerPermittedIdentifiers)

    static let refreshTaskId    = "com.pdcollect.ios.bg-refresh"
    static let processingTaskId = "com.pdcollect.ios.bg-processing"

    // MARK: - Dependencies

    private weak var healthKitManager: HealthKitManager?
    private weak var dataManager: DataManager?
    private weak var passiveSensor: PassiveSensorService?

    func configure(healthKit: HealthKitManager,
                   data: DataManager,
                   sensor: PassiveSensorService) {
        self.healthKitManager = healthKit
        self.dataManager      = data
        self.passiveSensor    = sensor
    }

    // MARK: - Registration (call once at app startup before any task fires)

    func registerTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskId,
            using: nil
        ) { [weak self] task in
            self?.handleRefresh(task: task as! BGAppRefreshTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.processingTaskId,
            using: nil
        ) { [weak self] task in
            self?.handleProcessing(task: task as! BGProcessingTask)
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
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Handlers

    private func handleRefresh(task: BGAppRefreshTask) {
        scheduleRefresh() // reschedule immediately for next cycle

        let op = Task {
            // Fetch latest HealthKit gait metrics and persist them
            if let hk = healthKitManager, let dm = dataManager {
                let metrics = await hk.fetchGaitMetrics(days: 1)
                if !metrics.isEmpty {
                    let csv = hk.csvString(for: metrics)
                    dm.appendGaitMetrics(csvString: csv)
                }
            }
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            op.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    private func handleProcessing(task: BGProcessingTask) {
        scheduleProcessing() // reschedule

        let op = Task {
            // Fetch up to 7 days of HealthKit data during a processing window
            if let hk = healthKitManager, let dm = dataManager {
                let metrics = await hk.fetchGaitMetrics(days: 7)
                if !metrics.isEmpty {
                    let csv = hk.csvString(for: metrics)
                    dm.appendGaitMetrics(csvString: csv)
                }
            }
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            op.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
