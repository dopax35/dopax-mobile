import Foundation
import AVFoundation
import HealthKit
import CoreMotion
import CoreBluetooth
import UserNotifications

/// Verifies setup health and permission states for the iOS application, matching Android's `SetupVerificationManager`.
/// Audits Camera, HealthKit, Motion/Pedometer, Bluetooth, and Notification permissions,
/// warning participants of any permission drift that could degrade research data collection.
final class SetupVerificationManager: NSObject, ObservableObject {

    static let shared = SetupVerificationManager()

    enum HealthStatus: String {
        case optimal = "OPTIMAL"
        case warning = "WARNING"
        case degraded = "DEGRADED"
    }

    struct HealthReport {
        let status: HealthStatus
        let issues: [String]
        let isCameraGranted: Bool
        let isHealthKitGranted: Bool
        let isMotionGranted: Bool
        let isBluetoothGranted: Bool
        let isNotificationsGranted: Bool
    }

    @Published private(set) var currentReport = HealthReport(
        status: .optimal,
        issues: [],
        isCameraGranted: true,
        isHealthKitGranted: true,
        isMotionGranted: true,
        isBluetoothGranted: true,
        isNotificationsGranted: true
    )

    private override init() {
        super.init()
    }

    func verifySetup(completion: ((HealthReport) -> Void)? = nil) {
        var issues: [String] = []

        // 1. Camera Permission
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let isCameraGranted = (cameraStatus == .authorized)
        if !isCameraGranted {
            issues.append("Camera access is disabled (required for face distance and gaze tracking).")
        }

        // 2. Motion / Pedometer Permission
        let isMotionGranted: Bool
        if #available(iOS 11.0, *) {
            let motionStatus = CMMotionActivityManager.authorizationStatus()
            isMotionGranted = (motionStatus == .authorized)
        } else {
            isMotionGranted = CMPedometer.isStepCountingAvailable()
        }
        if !isMotionGranted {
            issues.append("Motion & Fitness access is disabled (required for step and activity logging).")
        }

        // 3. Bluetooth Permission
        let bluetoothStatus: Bool
        if #available(iOS 13.0, *) {
            let cbStatus = CBCentralManager.authorization
            bluetoothStatus = (cbStatus == .allowedAlways)
        } else {
            bluetoothStatus = true
        }
        let isBluetoothGranted = bluetoothStatus
        if !isBluetoothGranted {
            issues.append("Bluetooth access is restricted (required for heart rate and Beanie sensors).")
        }

        // 4. Notifications Permission
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let isNotificationsGranted = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
            if !isNotificationsGranted {
                issues.append("Notifications are disabled (recommended for survey reminders).")
            }

            // 5. HealthKit Check
            let isHealthKitGranted = HKHealthStore.isHealthDataAvailable()

            let overallStatus: HealthStatus
            if !isCameraGranted || !isMotionGranted {
                overallStatus = .degraded
            } else if !isBluetoothGranted || !isNotificationsGranted {
                overallStatus = .warning
            } else {
                overallStatus = .optimal
            }

            let report = HealthReport(
                status: overallStatus,
                issues: issues,
                isCameraGranted: isCameraGranted,
                isHealthKitGranted: isHealthKitGranted,
                isMotionGranted: isMotionGranted,
                isBluetoothGranted: isBluetoothGranted,
                isNotificationsGranted: isNotificationsGranted
            )

            DispatchQueue.main.async {
                self.currentReport = report
                completion?(report)
            }
        }
    }
}
