import Foundation
import CoreBluetooth
import Combine

/// Central Bluetooth manager. Handles BLE scanning, connecting, and delegates to
/// HRBluetoothService and BeanieBluetoothService for characteristic handling.
///
/// Stability improvements (Android BleViewModel.kt parity):
///  - CBCentralManagerOptionRestoreIdentifierKey: CoreBluetooth restores state across bg kills
///  - CBConnectPeripheralOptionNotifyOnConnectionKey: OS reconnects automatically in background
///  - Scan-based fallback reconnect: indefinite scan loop after cached-peripheral connect fails
///  - Clean GATT teardown before reconnect avoids stale peripheral handles
class BluetoothManager: NSObject, ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var isPoweredOn = false
    @Published private(set) var isScanning = false
    @Published private(set) var discoveredHRDevices: [(id: UUID, name: String)] = []
    @Published private(set) var discoveredBeanieDevices: [(id: UUID, name: String)] = []
    
    // MARK: - Services
    
    let hrService = HRBluetoothService()
    let beanieService = BeanieBluetoothService()
    
    // MARK: - BLE UUIDs
    
    static let hrServiceUUID = CBUUID(string: "180D")
    static let beanieServiceUUID = CBUUID(string: "12345678-90AB-4CDE-8123-1234567890AB")
    
    // MARK: - Private
    
    private var centralManager: CBCentralManager!
    private var hrPeripheral: CBPeripheral?
    private var beaniePeripheral: CBPeripheral?
    private var dataManager: DataManager?
    private var userProfile: UserProfile?
    
    // Reconnection — exponential backoff then scan-based fallback
    private var hrReconnectTimer: Timer?
    private var beanieReconnectTimer: Timer?
    private var beanieReconnectScanTimer: Timer?   // scan-based fallback
    private var hrReconnectAttempts = 0
    private var beanieReconnectAttempts = 0
    private static let maxReconnectAttempts = 5    // after this, switch to scan fallback
    private static let baseReconnectDelay: TimeInterval = 3.0
    
    // Scan timeout
    private var scanTimer: Timer?
    private static let scanDuration: TimeInterval = 15.0
    
    // Track what we're scanning for
    private var scanningForHR = false
    private var scanningForBeanie = false
    private var scanningForBeanieReconnect = false  // silent background reconnect scan
    
    // Suppress reconnect when user explicitly disconnected
    private var userInitiatedBeanieDisconnect = false
    private var userInitiatedHRDisconnect = false
    
    static let shared = BluetoothManager()
    
    override private init() {
        super.init()
    }
    
    func setupCentralManager() {
        if centralManager != nil { return }
        // CBCentralManagerOptionRestoreIdentifierKey: CoreBluetooth recreates our
        // central manager (with the same identifier) when the app is relaunched after
        // a background kill, re-attaching any existing peripheral connections automatically.
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "com.pdcollect.bluetooth"]
        )
    }
    
    // MARK: - Public API
    
    func start(dataManager: DataManager, userProfile: UserProfile) {
        self.dataManager = dataManager
        self.userProfile = userProfile
        hrService.dataManager = dataManager
        beanieService.dataManager = dataManager
        
        // Auto-connect to saved devices
        if isPoweredOn {
            connectToSavedDevices()
        }
    }
    
    func stop() {
        stopScan()
        disconnectHR()
        disconnectBeanie()
    }
    
    // MARK: - Scanning
    
    func scanForHRDevices() {
        guard isPoweredOn else { return }
        scanningForHR = true
        discoveredHRDevices = []
        startScan()
    }
    
    func scanForBeanieDevices() {
        guard isPoweredOn else { return }
        scanningForBeanie = true
        discoveredBeanieDevices = []
        startScan()
    }
    
    private func startScan() {
        guard !isScanning else { return }
        
        // Scan with nil filter to discover ALL nearby BLE devices.
        // We filter by service UUID / name in didDiscover instead.
        centralManager.scanForPeripherals(withServices: nil,
                                          options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        isScanning = true
        
        // Auto-stop after timeout
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: Self.scanDuration, repeats: false) { [weak self] _ in
            self?.stopScan()
        }
    }
    
    func stopScan() {
        scanTimer?.invalidate()
        scanTimer = nil
        if isScanning {
            centralManager.stopScan()
            isScanning = false
        }
        scanningForHR = false
        scanningForBeanie = false
    }
    
    // MARK: - HR Connection
    
    func connectHRDevice(id: UUID) {
        stopScan()
        userInitiatedHRDisconnect = false
        guard let peripheral = centralManager.retrievePeripherals(withIdentifiers: [id]).first else { return }
        hrPeripheral = peripheral
        peripheral.delegate = hrService
        centralManager.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true
        ])
        hrService.status = .connecting
        
        // Save to profile
        userProfile?.hrDeviceIdentifier = id.uuidString
        userProfile?.hrDeviceName = peripheral.name ?? "HR Device"
    }
    
    func disconnectHR() {
        userInitiatedHRDisconnect = true
        hrReconnectTimer?.invalidate()
        hrReconnectTimer = nil
        hrReconnectAttempts = 0
        if let peripheral = hrPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        hrPeripheral = nil
        hrService.reset()
        
        userProfile?.hrDeviceIdentifier = ""
        userProfile?.hrDeviceName = ""
    }
    
    // MARK: - Beanie Connection
    
    func connectBeanieDevice(id: UUID) {
        stopScan()
        stopBeanieReconnectScan()
        userInitiatedBeanieDisconnect = false
        guard let peripheral = centralManager.retrievePeripherals(withIdentifiers: [id]).first else { return }
        beaniePeripheral = peripheral
        peripheral.delegate = beanieService
        // CBConnectPeripheralOptionNotifyOnConnectionKey: if the peripheral re-appears
        // in BT range while the app is in the background, iOS connects automatically.
        centralManager.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true
        ])
        beanieService.status = .connecting
        
        userProfile?.beanieDeviceIdentifier = id.uuidString
        userProfile?.beanieDeviceName = peripheral.name ?? "Beanie"
    }
    
    func disconnectBeanie() {
        userInitiatedBeanieDisconnect = true
        stopBeanieReconnectScan()
        beanieReconnectTimer?.invalidate()
        beanieReconnectTimer = nil
        beanieReconnectAttempts = 0
        if let peripheral = beaniePeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        beaniePeripheral = nil
        beanieService.reset()
        
        userProfile?.beanieDeviceIdentifier = ""
        userProfile?.beanieDeviceName = ""
    }
    
    // MARK: - Auto-reconnect (saved devices)
    
    private func connectToSavedDevices() {
        guard isPoweredOn else { return }
        
        if let hrId = userProfile?.hrDeviceIdentifier, !hrId.isEmpty,
           let uuid = UUID(uuidString: hrId) {
            if let peripheral = centralManager.retrievePeripherals(withIdentifiers: [uuid]).first {
                hrPeripheral = peripheral
                peripheral.delegate = hrService
                hrService.deviceName = userProfile?.hrDeviceName ?? "HR Device"
                centralManager.connect(peripheral, options: [
                    CBConnectPeripheralOptionNotifyOnConnectionKey: true
                ])
                hrService.status = .connecting
            }
        }
        
        if let beanieId = userProfile?.beanieDeviceIdentifier, !beanieId.isEmpty,
           let uuid = UUID(uuidString: beanieId) {
            if let peripheral = centralManager.retrievePeripherals(withIdentifiers: [uuid]).first {
                beaniePeripheral = peripheral
                peripheral.delegate = beanieService
                beanieService.deviceName = userProfile?.beanieDeviceName ?? "Beanie"
                centralManager.connect(peripheral, options: [
                    CBConnectPeripheralOptionNotifyOnConnectionKey: true
                ])
                beanieService.status = .connecting
            } else {
                // Peripheral not in cache (e.g. first launch after reinstall) — start a scan
                startBeanieReconnectScan()
            }
        }
    }
    
    // MARK: - HR Reconnect (exponential backoff)
    
    private func scheduleHRReconnect() {
        guard !userInitiatedHRDisconnect, hrReconnectAttempts < Self.maxReconnectAttempts else { return }
        hrReconnectAttempts += 1
        let delay = Self.baseReconnectDelay * pow(2.0, Double(min(hrReconnectAttempts - 1, 4)))
        let clampedDelay = min(delay, 120.0)
        
        hrReconnectTimer?.invalidate()
        hrReconnectTimer = Timer.scheduledTimer(withTimeInterval: clampedDelay, repeats: false) { [weak self] _ in
            self?.connectToSavedHR()
        }
    }
    
    private func connectToSavedHR() {
        guard let hrId = userProfile?.hrDeviceIdentifier, !hrId.isEmpty,
              let uuid = UUID(uuidString: hrId) else { return }
        if let peripheral = centralManager.retrievePeripherals(withIdentifiers: [uuid]).first {
            hrPeripheral = peripheral
            peripheral.delegate = hrService
            centralManager.connect(peripheral, options: [
                CBConnectPeripheralOptionNotifyOnConnectionKey: true
            ])
            hrService.status = .connecting
        }
    }
    
    // MARK: - Beanie Reconnect (exponential backoff → scan-based fallback)
    
    private func scheduleBeanieReconnect() {
        guard !userInitiatedBeanieDisconnect else { return }
        
        if beanieReconnectAttempts < Self.maxReconnectAttempts {
            // Phase 1: exponential backoff using cached peripheral handle
            beanieReconnectAttempts += 1
            let delay = Self.baseReconnectDelay * pow(2.0, Double(min(beanieReconnectAttempts - 1, 4)))
            let clampedDelay = min(delay, 60.0)
            
            beanieReconnectTimer?.invalidate()
            beanieReconnectTimer = Timer.scheduledTimer(withTimeInterval: clampedDelay, repeats: false) { [weak self] _ in
                self?.connectToSavedBeanie()
            }
        } else {
            // Phase 2: scan-based fallback (Android BleViewModel.kt: startAutoReconnectScan parity)
            // Runs indefinitely until the device reappears — never gives up.
            startBeanieReconnectScan()
        }
    }
    
    private func connectToSavedBeanie() {
        guard !userInitiatedBeanieDisconnect,
              let beanieId = userProfile?.beanieDeviceIdentifier, !beanieId.isEmpty,
              let uuid = UUID(uuidString: beanieId) else { return }
        
        if let peripheral = centralManager.retrievePeripherals(withIdentifiers: [uuid]).first {
            // Clean up the stale peripheral reference before reconnecting.
            // Keeping the old reference can cause CoreBluetooth to silently fail.
            if let old = beaniePeripheral, old !== peripheral {
                centralManager.cancelPeripheralConnection(old)
            }
            beaniePeripheral = peripheral
            peripheral.delegate = beanieService
            beanieService.reset()
            centralManager.connect(peripheral, options: [
                CBConnectPeripheralOptionNotifyOnConnectionKey: true
            ])
            beanieService.status = .connecting
        } else {
            // Not in cache — go straight to scan fallback
            startBeanieReconnectScan()
        }
    }
    
    // MARK: - Scan-Based Beanie Reconnect Fallback
    // Android parity: BleViewModel.startAutoReconnectScan() — scans 20s, waits 30s, repeats.
    // Runs until the device is found or userInitiatedBeanieDisconnect is set.
    
    private func startBeanieReconnectScan() {
        guard !userInitiatedBeanieDisconnect,
              let beanieId = userProfile?.beanieDeviceIdentifier, !beanieId.isEmpty else { return }
        stopBeanieReconnectScan()
        scanningForBeanieReconnect = true
        beanieService.status = .scanning
        
        centralManager.scanForPeripherals(
            withServices: [Self.beanieServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        
        // Stop scan after 20s and retry after 30s (Android: 20s scan, 30s gap)
        beanieReconnectScanTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: false) { [weak self] in
            guard let self else { return $0.invalidate() }
            self.centralManager.stopScan()
            self.scanningForBeanieReconnect = false
            guard !self.userInitiatedBeanieDisconnect else { return }
            // Re-scan after 30s
            self.beanieReconnectScanTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
                self?.startBeanieReconnectScan()
            }
        }
    }
    
    private func stopBeanieReconnectScan() {
        beanieReconnectScanTimer?.invalidate()
        beanieReconnectScanTimer = nil
        if scanningForBeanieReconnect {
            centralManager.stopScan()
            scanningForBeanieReconnect = false
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isPoweredOn = central.state == .poweredOn
        if isPoweredOn {
            connectToSavedDevices()
        }
    }
    
    /// CoreBluetooth state restoration (iOS background-kill recovery).
    /// Called when the app is relaunched by the system after being killed in the background.
    /// Re-attaches delegates to any peripherals that were connected at kill time.
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] else { return }
        
        let savedBeanieId = UUID(uuidString: userProfile?.beanieDeviceIdentifier ?? "")
        let savedHRId     = UUID(uuidString: userProfile?.hrDeviceIdentifier ?? "")
        
        for peripheral in peripherals {
            if peripheral.identifier == savedBeanieId {
                beaniePeripheral = peripheral
                peripheral.delegate = beanieService
                beanieService.deviceName = peripheral.name ?? userProfile?.beanieDeviceName ?? "Beanie"
                beanieService.deviceAddress = peripheral.identifier.uuidString
            } else if peripheral.identifier == savedHRId {
                hrPeripheral = peripheral
                peripheral.delegate = hrService
                hrService.deviceName = peripheral.name ?? userProfile?.hrDeviceName ?? "HR Device"
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                       advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let rawName = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = rawName ?? "Unknown (\(peripheral.identifier.uuidString.prefix(8))…)"
        let id = peripheral.identifier
        let advServiceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        
        // Silent background reconnect scan — check if this is our saved beanie
        if scanningForBeanieReconnect {
            let savedBeanieId = UUID(uuidString: userProfile?.beanieDeviceIdentifier ?? "")
            let isOurBeanie = id == savedBeanieId
                || advServiceUUIDs.contains(Self.beanieServiceUUID)
                || BeanieRegistry.isLikelyBeanie(name)
            
            if isOurBeanie && (savedBeanieId == nil || id == savedBeanieId) {
                stopBeanieReconnectScan()
                beanieReconnectAttempts = 0
                let deviceToConnect: CBPeripheral
                if let existing = centralManager.retrievePeripherals(withIdentifiers: [id]).first {
                    deviceToConnect = existing
                } else {
                    deviceToConnect = peripheral
                }
                beaniePeripheral = deviceToConnect
                deviceToConnect.delegate = beanieService
                beanieService.reset()
                beanieService.deviceName = name
                beanieService.deviceAddress = id.uuidString
                centralManager.connect(deviceToConnect, options: [
                    CBConnectPeripheralOptionNotifyOnConnectionKey: true
                ])
                beanieService.status = .connecting
            }
            return
        }
        
        // Check for HR device — show ALL named devices so user can pick
        if scanningForHR {
            if !discoveredHRDevices.contains(where: { $0.id == id }) {
                DispatchQueue.main.async {
                    self.discoveredHRDevices.append((id: id, name: name))
                }
            }
        }
        
        // Check for Beanie device — match by advertised service UUID OR by name keywords
        if scanningForBeanie {
            let isBeanie = advServiceUUIDs.contains(Self.beanieServiceUUID)
                        || BeanieRegistry.isLikelyBeanie(name)
            if isBeanie && !discoveredBeanieDevices.contains(where: { $0.id == id }) {
                DispatchQueue.main.async {
                    self.discoveredBeanieDevices.append((id: id, name: name))
                }
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if peripheral === hrPeripheral {
            hrReconnectAttempts = 0
            hrService.status = .discovering
            hrService.deviceName = peripheral.name ?? userProfile?.hrDeviceName ?? "HR Device"
            peripheral.discoverServices([Self.hrServiceUUID])
        } else if peripheral === beaniePeripheral {
            beanieReconnectAttempts = 0
            stopBeanieReconnectScan()
            beanieService.status = .discovering
            beanieService.deviceName = peripheral.name ?? userProfile?.beanieDeviceName ?? "Beanie"
            beanieService.deviceAddress = peripheral.identifier.uuidString
            peripheral.discoverServices([Self.beanieServiceUUID])
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral === hrPeripheral {
            hrService.isConnected = false
            hrService.status = .disconnected
            hrService.currentBPM = 0
            if !userInitiatedHRDisconnect {
                scheduleHRReconnect()
            }
        } else if peripheral === beaniePeripheral {
            beanieService.isConnected = false
            beanieService.status = .disconnected
            beanieService.parser.resetBuffer()
            if !userInitiatedBeanieDisconnect {
                scheduleBeanieReconnect()
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if peripheral === hrPeripheral {
            hrService.status = .disconnected
            scheduleHRReconnect()
        } else if peripheral === beaniePeripheral {
            beanieService.status = .disconnected
            scheduleBeanieReconnect()
        }
    }
    
}

// MARK: - BLEDeviceStatus (shared enum for HR + Beanie)

enum BLEDeviceStatus: String {
    case idle        = "Not set up"
    case scanning    = "Scanning…"
    case connecting  = "Connecting"
    case discovering = "Discovering"
    case ready       = "Connected"
    case disconnected = "Disconnected"
    
    var isActive: Bool {
        switch self {
        case .ready: return true
        default: return false
        }
    }
}
