import SwiftUI
import AVFoundation

// MARK: - App Delegate (needed for UIApplication subclassing via LoggingApplication)

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Wire the LoggingApplication's data manager reference
        // AppState is resolved via environment; here we use a shared accessor
        return true
    }
}

// MARK: - App Entry Point

@main
struct PDCollectiOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    // Wire touch logger's data manager after the environment is available
                    if let loggingApp = UIApplication.shared as? LoggingApplication {
                        loggingApp.dataManager = appState.dataManager
                    }
                    // Request camera access for face distance — do not block launch
                    requestCameraPermissionIfNeeded()
                }
        }
    }

    // MARK: - Camera Permission

    private func requestCameraPermissionIfNeeded() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            appState.startFaceDistance()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { DispatchQueue.main.async { appState.startFaceDistance() } }
            }
        default:
            break // denied or restricted — face distance won't run
        }
    }
}
