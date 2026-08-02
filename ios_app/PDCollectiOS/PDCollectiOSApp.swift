import SwiftUI
import AVFoundation
import FirebaseCore
import GoogleSignIn

// MARK: - App Delegate (needed for UIApplication subclassing via LoggingApplication)

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        
        // Instantiate CBCentralManager during launch to support background restoration
        BluetoothManager.shared.setupCentralManager()
        
        // Register background tasks early to prevent startup crash
        BackgroundCollectionManager.shared.registerTasks()
        
        return true
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
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
                // App-wide default accent: without this, every control that
                // doesn't set an explicit .tint (nav bar back buttons, links,
                // toggles, alerts, unstyled buttons) falls back to the generic
                // iOS system blue instead of the Dopa-X brand blue. Setting it
                // once here is what makes those default-styled elements
                // consistent with the explicitly-tinted ones throughout the
                // app. (July 2026 color-consistency pass.)
                .tint(.dopaxBlue)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                .onAppear {
                    // Wire touch logger's data manager after the environment is available
                    if let loggingApp = UIApplication.shared as? LoggingApplication {
                        loggingApp.dataManager = appState.dataManager
                        loggingApp.isCollecting = appState.isCollecting
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
