import Foundation
import UIKit

/// Listens to UIApplication lifecycle notifications and writes app foreground/background
/// events to disk — mirrors Android's DataAccessibilityService app-switch logging (apps.csv).
class AppEventLogger: ObservableObject {

    private(set) var isRunning = false
    private var dataManager: DataManager?
    private var lastEventTimestamp: Int64 = 0
    private let bundleId = Bundle.main.bundleIdentifier ?? "com.pdcollect.ios"
    private let queue = DispatchQueue(label: "com.pdcollect.app-event-logger", qos: .utility)

    // Notification observers
    private var tokens: [NSObjectProtocol] = []

    func start(dataManager: DataManager) {
        guard !isRunning else { return }
        self.dataManager = dataManager
        isRunning = true
        lastEventTimestamp = nowMs()

        let center = NotificationCenter.default

        tokens.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                         object: nil, queue: nil) { [weak self] _ in
            self?.log(event: "foreground")
        })
        tokens.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                         object: nil, queue: nil) { [weak self] _ in
            self?.log(event: "active")
        })
        tokens.append(center.addObserver(forName: UIApplication.willResignActiveNotification,
                                         object: nil, queue: nil) { [weak self] _ in
            self?.log(event: "inactive")
        })
        tokens.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                         object: nil, queue: nil) { [weak self] _ in
            self?.log(event: "background")
        })

        log(event: "app_launch")
    }

    func stop() {
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
        tokens = []
        isRunning = false
    }

    // MARK: - Private

    private func log(event: String) {
        guard let dm = dataManager else { return }
        let now = nowMs()
        let duration = lastEventTimestamp == 0 ? 0 : now - lastEventTimestamp
        lastEventTimestamp = now

        let ev = AppEvent(
            timestampMs: now,
            event: event,
            bundleId: bundleId,
            durationMs: duration
        )
        queue.async { dm.writeAppEvent(ev) }
    }

    private func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
