import SwiftUI
import Combine

class AppState: ObservableObject {

    // MARK: - Existing managers

    @Published var userProfile: UserProfile
    let healthKitManager = HealthKitManager()
    let dataManager: DataManager
    let motionManager = CoreMotionManager()  // used during active tests only

    // MARK: - Gamification
    let gamification = GamificationManager()

    // MARK: - New passive-collection managers (iPhone branch)

    let passiveSensor  = PassiveSensorService()
    let faceDistance   = FaceDistanceManager()
    let appEventLogger = AppEventLogger()
    let bgCollection   = BackgroundCollectionManager()

    // MARK: - Bluetooth
    let bluetoothManager = BluetoothManager()

    /// Whether the user has enabled passive background collection from Settings.
    @Published var isCollecting: Bool {
        didSet {
            UserDefaults.standard.set(isCollecting, forKey: "isCollecting")
            isCollecting ? startCollection() : stopCollection()
        }
    }

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        let profile = UserProfile()
        self.userProfile = profile
        self.dataManager = DataManager(userId: profile.userId)
        self.isCollecting = UserDefaults.standard.bool(forKey: "isCollecting")

        profile.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        profile.$userId
            .dropFirst()
            .sink { [weak self] newId in self?.dataManager.userId = newId }
            .store(in: &cancellables)

        bgCollection.configure(healthKit: healthKitManager,
                               data: dataManager,
                               sensor: passiveSensor)
        bgCollection.registerTasks()

        // Resume collection if it was active before the app was killed
        if isCollecting { startCollection() }
    }

    // MARK: - Collection Control

    private let keystrokeSync = KeystrokeSync()

    func startCollection() {
        passiveSensor.start(dataManager: dataManager)
        appEventLogger.start(dataManager: dataManager)
        bgCollection.scheduleAll()
        // Write daily profile snapshot
        dataManager.writeProfileSnapshot(profile: userProfile)
        // Import any buffered keystrokes from keyboard extension
        keystrokeSync.importBufferedKeystrokes(dataManager: dataManager)
        // FaceDistanceManager is started separately after camera permission is granted
    }

    func stopCollection() {
        passiveSensor.stop()
        appEventLogger.stop()
        faceDistance.stop()
    }

    /// Call after AVCaptureDevice.requestAccess returns .authorized
    func startFaceDistance() {
        guard isCollecting else { return }
        faceDistance.start(dataManager: dataManager)
    }
}
