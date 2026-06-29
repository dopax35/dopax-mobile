import Foundation
import CoreBluetooth
import Combine

/// Central Bluetooth manager. Handles BLE scanning, connecting, and delegates to
/// HRBluetoothService and BeanieBluetoothService for characteristic handling.
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
    
    // Reconnection
    private var hrReconnectTimer: Timer?
    private var beanieReconnectTimer: Timer?
    private var hrReconnectAttempts = 0
    private var beanieReconnectAttempts = 0
    private static let maxReconnectAttempts = 10
    private static let baseReconnectDelay: TimeInterval = 5.0
    
    // Scan timeout
    private var scanTimer: Timer?
    private static let scanDuration: TimeInterval = 15.0
    
    // Track what we're scanning for
    private var scanningForHR = false
    private var scanningForBeanie = false
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Public API
    
    func start(dataManager: DataManager, userProfile: UserProfile) {
        self.dataManager = dataManager
        self.userProfile = userProfile
        hrService.dataManager = dataManager
        beanieService.dataManager = dataManager
        
        // Auto-connect to saved devices
        connectToSavedDevices()
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
        guard let peripheral = centralManager.retrievePeripherals(withIdentifiers: [id]).first else { return }
        hrPeripheral = peripheral
        peripheral.delegate = hrService
        centralManager.connect(peripheral, options: nil)
        hrService.status = .connecting
        
        // Save to profile
        userProfile?.hrDeviceIdentifier = id.uuidString
        userProfile?.hrDeviceName = peripheral.name ?? "HR Device"
    }
    
    func disconnectHR() {
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
        guard let peripheral = centralManager.retrievePeripherals(withIdentifiers: [id]).first else { return }
        beaniePeripheral = peripheral
        peripheral.delegate = beanieService
        centralManager.connect(peripheral, options: nil)
        beanieService.status = .connecting
        
        userProfile?.beanieDeviceIdentifier = id.uuidString
        userProfile?.beanieDeviceName = peripheral.name ?? "Beanie"
    }
    
    func disconnectBeanie() {
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
    
    // MARK: - Auto-reconnect
    
    private func connectToSavedDevices() {
        guard isPoweredOn else { return }
        
        if let hrId = userProfile?.hrDeviceIdentifier, !hrId.isEmpty,
           let uuid = UUID(uuidString: hrId) {
            if let peripheral = centralManager.retrievePeripherals(withIdentifiers: [uuid]).first {
                hrPeripheral = peripheral
                peripheral.delegate = hrService
                hrService.deviceName = userProfile?.hrDeviceName ?? "HR Device"
                centralManager.connect(peripheral, options: nil)
                hrService.status = .connecting
            }
        }
        
        if let beanieId = userProfile?.beanieDeviceIdentifier, !beanieId.isEmpty,
           let uuid = UUID(uuidString: beanieId) {
            if let peripheral = centralManager.retrievePeripherals(withIdentifiers: [uuid]).first {
                beaniePeripheral = peripheral
                peripheral.delegate = beanieService
                beanieService.deviceName = userProfile?.beanieDeviceName ?? "Beanie"
                centralManager.connect(peripheral, options: nil)
                beanieService.status = .connecting
            }
        }
    }
    
    private func scheduleHRReconnect() {
        guard hrReconnectAttempts < Self.maxReconnectAttempts else { return }
        hrReconnectAttempts += 1
        let delay = Self.baseReconnectDelay * pow(2.0, Double(min(hrReconnectAttempts - 1, 5)))
        let clampedDelay = min(delay, 300.0)
        
        hrReconnectTimer?.invalidate()
        hrReconnectTimer = Timer.scheduledTimer(withTimeInterval: clampedDelay, repeats: false) { [weak self] _ in
            self?.connectToSavedHR()
        }
    }
    
    private func scheduleBeanieReconnect() {
        guard beanieReconnectAttempts < Self.maxReconnectAttempts else { return }
        beanieReconnectAttempts += 1
        let delay = Self.baseReconnectDelay * pow(2.0, Double(min(beanieReconnectAttempts - 1, 5)))
        let clampedDelay = min(delay, 300.0)
        
        beanieReconnectTimer?.invalidate()
        beanieReconnectTimer = Timer.scheduledTimer(withTimeInterval: clampedDelay, repeats: false) { [weak self] _ in
            self?.connectToSavedBeanie()
        }
    }
    
    private func connectToSavedHR() {
        guard let hrId = userProfile?.hrDeviceIdentifier, !hrId.isEmpty,
              let uuid = UUID(uuidString: hrId) else { return }
        if let peripheral = centralManager.retrievePeripherals(withIdentifiers: [uuid]).first {
            hrPeripheral = peripheral
            peripheral.delegate = hrService
            centralManager.connect(peripheral, options: nil)
            hrService.status = .connecting
        }
    }
    
    private func connectToSavedBeanie() {
        guard let beanieId = userProfile?.beanieDeviceIdentifier, !beanieId.isEmpty,
              let uuid = UUID(uuidString: beanieId) else { return }
        if let peripheral = centralManager.retrievePeripherals(withIdentifiers: [uuid]).first {
            beaniePeripheral = peripheral
            peripheral.delegate = beanieService
            centralManager.connect(peripheral, options: nil)
            beanieService.status = .connecting
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
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                       advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let rawName = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = rawName ?? "Unknown (\(peripheral.identifier.uuidString.prefix(8))…)"
        let id = peripheral.identifier
        let advServiceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        
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
    
    /// Common HR monitor name patterns
    private static func isLikelyHRDevice(_ name: String) -> Bool {
        let lower = name.lowercased()
        let hrKeywords = ["polar", "h10", "h9", "h7", "heart", "hr", "verity", "oh1",
                          "wahoo", "tickr", "garmin", "coospo", "magene", "scosche"]
        return hrKeywords.contains { lower.contains($0) }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if peripheral === hrPeripheral {
            hrReconnectAttempts = 0
            hrService.status = .discovering
            hrService.deviceName = peripheral.name ?? userProfile?.hrDeviceName ?? "HR Device"
            peripheral.discoverServices([Self.hrServiceUUID])
        } else if peripheral === beaniePeripheral {
            beanieReconnectAttempts = 0
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
            scheduleHRReconnect()
        } else if peripheral === beaniePeripheral {
            beanieService.isConnected = false
            beanieService.status = .disconnected
            beanieService.parser.resetBuffer()
            scheduleBeanieReconnect()
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
