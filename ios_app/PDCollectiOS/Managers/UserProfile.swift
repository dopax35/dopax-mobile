import Foundation
import Combine
import Security

class UserProfile: ObservableObject {
    @Published var consentGiven: Bool      { didSet { save("consentGiven", consentGiven) } }
    @Published var profileComplete: Bool   { didSet { save("profileComplete", profileComplete) } }
    @Published var userId: String          { didSet { save("userId", userId); saveToKeychain(userId) } }
    @Published var age: String             { didSet { save("age", age) } }
    @Published var gender: String          { didSet { save("gender", gender) } }
    @Published var dominantHand: String    { didSet { save("dominantHand", dominantHand) } }
    @Published var affectedSide: String    { didSet { save("affectedSide", affectedSide) } }
    @Published var medications: [Medication] {
        didSet {
            if let data = try? JSONEncoder().encode(medications) {
                UserDefaults.standard.set(data, forKey: "medications")
            }
        }
    }
    // MARK: - Bluetooth Device Pairing

    @Published var hrDeviceIdentifier: String  { didSet { save("hrDeviceIdentifier", hrDeviceIdentifier) } }
    @Published var hrDeviceName: String        { didSet { save("hrDeviceName", hrDeviceName) } }
    @Published var beanieDeviceIdentifier: String { didSet { save("beanieDeviceIdentifier", beanieDeviceIdentifier) } }
    @Published var beanieDeviceName: String     { didSet { save("beanieDeviceName", beanieDeviceName) } }

    init() {
        let d = UserDefaults.standard
        self.consentGiven = d.bool(forKey: "consentGiven")
        self.profileComplete = d.bool(forKey: "profileComplete")
        self.age = d.string(forKey: "age") ?? ""
        self.gender = d.string(forKey: "gender") ?? ""
        self.dominantHand = d.string(forKey: "dominantHand") ?? "Right"
        self.affectedSide = d.string(forKey: "affectedSide") ?? "Left"
        self.hrDeviceIdentifier = d.string(forKey: "hrDeviceIdentifier") ?? ""
        self.hrDeviceName = d.string(forKey: "hrDeviceName") ?? ""
        self.beanieDeviceIdentifier = d.string(forKey: "beanieDeviceIdentifier") ?? ""
        self.beanieDeviceName = d.string(forKey: "beanieDeviceName") ?? ""

        if let data = d.data(forKey: "medications") {
            if let meds = try? JSONDecoder().decode([Medication].self, from: data) {
                self.medications = meds
            } else if let stringMeds = try? JSONDecoder().decode([String].self, from: data) {
                // Migration path for legacy string array
                self.medications = stringMeds.map { Medication(name: $0, dosage: "") }
            } else {
                self.medications = []
            }
        } else {
            self.medications = []
        }

        // userId resolution order:
        //   1. UserDefaults   — written every session once set
        //   2. Keychain       — survives app reinstall
        //   3. Generate new   — first-ever launch
        if let uid = d.string(forKey: "userId"), !uid.isEmpty {
            self.userId = uid
            // Keep Keychain in sync (may be missing after first update)
            saveToKeychain(uid)
        } else if let keychainId = getFromKeychain(), !keychainId.isEmpty {
            // Survived reinstall — restore into UserDefaults
            self.userId = keychainId
            d.set(keychainId, forKey: "userId")
        } else {
            let newId = "pd_" + UUID().uuidString.prefix(8).lowercased()
            self.userId = newId
            d.set(newId, forKey: "userId")
            saveToKeychain(newId)
        }
    }

    func clearAll() {
        ["consentGiven","profileComplete","userId","age","gender","dominantHand","affectedSide","medications",
         "hrDeviceIdentifier","hrDeviceName","beanieDeviceIdentifier","beanieDeviceName"]
            .forEach { UserDefaults.standard.removeObject(forKey: $0) }
        deleteFromKeychain()
        consentGiven = false
        profileComplete = false
        let newId = "pd_" + UUID().uuidString.prefix(8).lowercased()
        userId = newId
        age = ""; gender = ""; dominantHand = "Right"; affectedSide = "Left"; medications = []
        hrDeviceIdentifier = ""; hrDeviceName = ""
        beanieDeviceIdentifier = ""; beanieDeviceName = ""
    }

    private func save(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }

    // MARK: - Keychain
    private func saveToKeychain(_ value: String) {
        let data = Data(value.utf8)
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: "userId", kSecValueData: data] as [String: Any]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func getFromKeychain() -> String? {
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: "userId", kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne] as [String: Any]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteFromKeychain() {
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: "userId"] as [String: Any]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Firebase Sync

    func toMap() -> [String: Any] {
        var map: [String: Any] = [
            "consentGiven": consentGiven,
            "profileComplete": profileComplete,
            "userId": userId,
            "age": age,
            "gender": gender,
            "dominantHand": dominantHand,
            "affectedSide": affectedSide
        ]
        
        let medsList = medications.map { ["name": $0.name, "dosage": $0.dosage] }
        map["medications"] = medsList
        
        return map
    }
    
    func mergeFromCloud(from map: [String: Any]) {
        if !consentGiven, let consent = map["consentGiven"] as? Bool { self.consentGiven = consent }
        if !profileComplete, let complete = map["profileComplete"] as? Bool { self.profileComplete = complete }
        if age.isEmpty, let a = map["age"] as? String { self.age = a }
        if gender.isEmpty, let g = map["gender"] as? String { self.gender = g }
        if dominantHand == "Right", let hand = map["dominantHand"] as? String, !hand.isEmpty { self.dominantHand = hand }
        if affectedSide == "Left", let side = map["affectedSide"] as? String, !side.isEmpty { self.affectedSide = side }
        
        if medications.isEmpty, let medsArray = map["medications"] as? [[String: Any]] {
            self.medications = medsArray.compactMap { dict in
                guard let name = dict["name"] as? String else { return nil }
                let dosage = dict["dosage"] as? String ?? ""
                return Medication(name: name, dosage: dosage)
            }
        }
    }
    
    func update(from map: [String: Any]) {
        if let consent = map["consentGiven"] as? Bool { self.consentGiven = consent }
        if let complete = map["profileComplete"] as? Bool { self.profileComplete = complete }
        if let uid = map["userId"] as? String { self.userId = uid }
        if let a = map["age"] as? String { self.age = a }
        if let g = map["gender"] as? String { self.gender = g }
        if let hand = map["dominantHand"] as? String { self.dominantHand = hand }
        if let side = map["affectedSide"] as? String { self.affectedSide = side }
        
        if let medsArray = map["medications"] as? [[String: Any]] {
            self.medications = medsArray.compactMap { dict in
                guard let name = dict["name"] as? String else { return nil }
                let dosage = dict["dosage"] as? String ?? ""
                return Medication(name: name, dosage: dosage)
            }
        }
    }
}
