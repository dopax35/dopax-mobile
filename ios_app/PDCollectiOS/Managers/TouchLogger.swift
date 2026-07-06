import UIKit
import Foundation

/// Subclasses UIApplication to intercept every UIEvent and log touch coordinates,
/// inter-tap intervals, and scroll distances to disk.
///
/// This is the iOS equivalent of Android's DataAccessibilityService for touch events.
/// Limitation: only captures touches within our own app (system-wide touch capture
/// requires a private entitlement on iOS), matching the most ethical and AppStore-safe approach.
///
/// Activate by adding to PDCollectiOSApp:
///   @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
/// and setting the principalClass in the @main struct.
class LoggingApplication: UIApplication {

    // MARK: - Injected dependency

    /// Set by AppDelegate after the app launches.
    var dataManager: DataManager?

    /// Set to true when passive collection is active.
    var isCollecting: Bool = false

    // MARK: - State

    private var lastTapTimestamp: Int64 = 0
    private let queue = DispatchQueue(label: "com.pdcollect.touch-logger", qos: .utility)

    // MARK: - Override

    override func sendEvent(_ event: UIEvent) {
        super.sendEvent(event)

        guard isCollecting, event.type == .touches, let dm = dataManager else { return }

        for touch in event.allTouches ?? [] {
            let phase = touch.phase
            guard phase == .began || phase == .ended else { continue }

            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let loc   = touch.location(in: nil) // window coords
            let pressure: Float

            // Force Touch available only on 3D-Touch devices; falls back to 0
            if touch.maximumPossibleForce > 0 {
                pressure = Float(touch.force / touch.maximumPossibleForce)
            } else {
                pressure = 0
            }

            let interval = lastTapTimestamp == 0 ? 0 : nowMs - lastTapTimestamp
            if phase == .ended { lastTapTimestamp = nowMs }

            let action = phase == .began ? "tap_down" : "tap_up"
            let ev = TouchEvent(
                timestampMs: nowMs,
                action: action,
                x: Float(loc.x),
                y: Float(loc.y),
                pressure: pressure,
                tapIntervalMs: interval
            )

            queue.async { dm.writeTouchEvent(ev) }
        }
    }
}
