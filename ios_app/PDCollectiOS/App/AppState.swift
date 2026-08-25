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

    // MARK: - Daily sessions (Today screen)
    let sessionManager: SessionManager

    // MARK: - New passive-collection managers (iPhone branch)

    let passiveSensor  = PassiveSensorService()
    let faceDistance   = FaceDistanceManager()
    let appEventLogger = AppEventLogger()
    let sensorKitManager = SensorKitManager()
    let bgCollection   = BackgroundCollectionManager.shared
    let keepAliveManager = BackgroundKeepAliveManager.shared

    // MARK: - Bluetooth
    let bluetoothManager = BluetoothManager.shared

    // MARK: - Auth
    let authManager = AuthManager()

    /// True when the user tapped "Continue without signing in". Persisted so
    /// it survives an app restart (they stay past LoginView until they sign in
    /// or reset). Cleared on sign-out so the LoginView is shown again.
    @Published var hasSkippedLogin: Bool

    /// Whether the user has enabled passive background collection from Settings.
    @Published var isCollecting: Bool {
        didSet {
            UserDefaults.standard.set(isCollecting, forKey: "isCollecting")
            // Sync to LoggingApplication (touch logger gate)
            if let loggingApp = UIApplication.shared as? LoggingApplication {
                loggingApp.isCollecting = isCollecting
            }
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
        self.sessionManager = SessionManager(schedule: profile.sessionSchedule)
        if let val = UserDefaults.standard.object(forKey: "isCollecting") as? Bool {
            self.isCollecting = val
        } else {
            self.isCollecting = true
            UserDefaults.standard.set(true, forKey: "isCollecting")
        }
        self.hasSkippedLogin = UserDefaults.standard.bool(forKey: "hasSkippedLogin")

        profile.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Re-schedule BG tasks when the autoUpload toggle changes.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .filter { _ in UserDefaults.standard.object(forKey: "autoUploadEnabled") != nil }
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.bgCollection.scheduleAll() }
            .store(in: &cancellables)

        profile.$userId
            .dropFirst()
            .sink { [weak self] newId in self?.dataManager.userId = newId }
            .store(in: &cancellables)

        // Session windows are user-editable, so keep the schedule current.
        // CombineLatest3 replays the current values immediately; dropFirst
        // skips that so we don't rebuild the schedule we just constructed.
        Publishers.CombineLatest3(profile.$testTimeMorning,
                                  profile.$testTimeNoon,
                                  profile.$testTimeEvening)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] morning, noon, night in
                self?.sessionManager.updateSchedule(
                    SessionSchedule(morningText: morning, noonText: noon, nightText: night))
            }
            .store(in: &cancellables)

        // A window may have opened or the day rolled over while backgrounded.
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sessionManager.refresh() }
            .store(in: &cancellables)

        // Every test screen already reports to gamification when it saves.
        // Forwarding that to the session layer means the hub learns a test
        // finished without any test screen needing to know sessions exist.
        // The manager ignores anything it did not itself launch.
        gamification.onCompletion = { [weak self] testType, score in
            guard let self else { return }
            DispatchQueue.main.async {
                self.sessionManager.testDidComplete(testId: testType, score: score)
            }
        }

        sensorKitManager.configure(dataManager: dataManager)

        bgCollection.configure(healthKit: healthKitManager,
                               data: dataManager,
                               sensor: passiveSensor,
                               sensorKit: sensorKitManager)

        // Fetch SensorKit data whenever app becomes active
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] _ in
                guard let self, self.isCollecting else { return }
                self.sensorKitManager.fetchSensorKitData()
            }
            .store(in: &cancellables)

        // Import keystrokes whenever app becomes active (foreground)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] _ in
                guard let self, self.isCollecting else { return }
                self.keystrokeSync.importBufferedKeystrokes(dataManager: self.dataManager)
            }
            .store(in: &cancellables)

        // Attempt any pending backup uploads whenever the app becomes
        // active — BGProcessingTask (the background-only path) is best
        // effort and iOS may not run it as often as requested, especially
        // for an app that isn't opened daily. Since most participants do
        // open the app at least once a day for tests, this makes "backs up
        // automatically once a day" actually reliable in practice rather
        // than dependent on an opportunistic OS wakeup that might not come.
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] _ in
                guard let self else { return }
                Task {
                    await BackgroundCollectionManager.uploadPendingDates(
                        dataManager: self.dataManager, requireWifiUnlessStale: true
                    )
                }
            }
            .store(in: &cancellables)

        // Backfill step/walking history every time the app comes to the
        // foreground (see PedometerHistoryService) — fills in the hours
        // since the last sync even if the app was never opened during them.
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await PedometerHistoryService.shared.syncHistory(dataManager: self.dataManager) }
            }
            .store(in: &cancellables)

        // Same idea, for activity-type context (walking/running/stationary/
        // etc. — see MotionActivityHistoryService), a second all-day,
        // co-processor-backed signal independent of the app being open.
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await MotionActivityHistoryService.shared.syncHistory(dataManager: self.dataManager) }
            }
            .store(in: &cancellables)

        // Resume collection if it was active before the app was killed
        if isCollecting { startCollection() }
    }

    // MARK: - Collection Control

    private let keystrokeSync = KeystrokeSync()

    func startCollection() {
        // Pre-create ALL expected CSV files with their headers for today so no files are
        // ever missing from a day's directory in the research data — matches Android's
        // DataManager.initializeAllDailyLogs() called from PDCollectService.onStartCommand().
        dataManager.initializeDailyFiles()
        passiveSensor.start(dataManager: dataManager)
        keepAliveManager.start()
        appEventLogger.start(dataManager: dataManager)
        bgCollection.scheduleAll()
        // Wire Bluetooth so HR and Beanie data gets written to disk
        bluetoothManager.start(dataManager: dataManager, userProfile: userProfile)
        // Write daily profile snapshot
        dataManager.writeProfileSnapshot(profile: userProfile)
        // Import any buffered keystrokes from keyboard extension
        keystrokeSync.importBufferedKeystrokes(dataManager: dataManager)
        // Backfill step/walking history from CMPedometer, plus activity-type
        // context from CMMotionActivityManager (both cover hours the app
        // wasn't open — see PedometerHistoryService / MotionActivityHistoryService)
        Task { await PedometerHistoryService.shared.syncHistory(dataManager: dataManager) }
        Task { await MotionActivityHistoryService.shared.syncHistory(dataManager: dataManager) }
        sensorKitManager.fetchSensorKitData()
        // FaceDistanceManager is started separately after camera permission is granted
    }

    func stopCollection() {
        passiveSensor.stop()
        keepAliveManager.stop()
        appEventLogger.stop()
        faceDistance.stop()
        bluetoothManager.stop()
    }

    // MARK: - Auth Helpers

    /// Called when the user taps "Continue without signing in" in LoginView.
    /// Sets a persistent flag so the app routes past LoginView on next launch too.
    func skipSignIn() {
        hasSkippedLogin = true
        UserDefaults.standard.set(true, forKey: "hasSkippedLogin")
    }

    /// Called on sign-out. Clears the skip flag so the LoginView is shown again
    /// without erasing any local profile data.
    func clearSkipSignIn() {
        hasSkippedLogin = false
        UserDefaults.standard.removeObject(forKey: "hasSkippedLogin")
    }

    /// Call after AVCaptureDevice.requestAccess returns .authorized
    func startFaceDistance() {
        faceDistance.start(dataManager: dataManager)
    }
}
