import Foundation
import Combine
import Security

class UserProfile: ObservableObject {
    @Published var consentGiven: Bool      { didSet { save("consentGiven", consentGiven) } }
    @Published var profileComplete: Bool   { didSet { save("profileComplete", profileComplete) } }
    @Published var userId: String          { didSet { save("userId", userId); UserProfile.saveToKeychain(userId) } }
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

    // MARK: - Onboarding v2 (Figma flow) — additive; legacy users fill these on upgrade
    @Published var displayName: String         { didSet { save("displayName", displayName) } }
    @Published var yearOfBirth: String         { didSet { save("yearOfBirth", yearOfBirth) } }
    @Published var testTimeMorning: String     { didSet { save("testTimeMorning", testTimeMorning) } }
    /// Third daily window. Added for the Today redesign, which schedules
    /// morning/noon/night. Defaulted rather than migrated so existing
    /// participants keep the two windows they already chose.
    @Published var testTimeNoon: String        { didSet { save("testTimeNoon", testTimeNoon) } }
    @Published var testTimeEvening: String     { didSet { save("testTimeEvening", testTimeEvening) } }
    @Published var testTimeCustom: String      { didSet { save("testTimeCustom", testTimeCustom) } }
    @Published var healthAppleStatus: String   { didSet { save("healthAppleStatus", healthAppleStatus) } }
    @Published var healthStravaStatus: String  { didSet { save("healthStravaStatus", healthStravaStatus) } }
    @Published var notificationsOptIn: Bool    { didSet { save("notificationsOptIn", notificationsOptIn) } }
    @Published var keyboardOptIn: Bool         { didSet { save("keyboardOptIn", keyboardOptIn) } }
    /// Set when the Figma onboarding flow (incl. session windows) finishes.
    @Published var onboardingVersion: Int      { didSet { save("onboardingVersion", onboardingVersion) } }
    @Published var consentSignatureName: String { didSet { save("consentSignatureName", consentSignatureName) } }
    @Published var consentSignatureImage: String { didSet { save("consentSignatureImage", consentSignatureImage) } }
    @Published var consentLocale: String       { didSet { save("consentLocale", consentLocale) } }

    /// Legacy users who completed v1 still need v2 fields (session windows).
    var needsOnboardingV2: Bool {
        onboardingVersion < 2 || testTimeCustom.isEmpty
    }

    /// The three daily windows the Today screen schedules against. The design's
    /// "Night Session" is this profile's evening window.
    var sessionSchedule: SessionSchedule {
        SessionSchedule(morningText: testTimeMorning,
                        noonText: testTimeNoon,
                        nightText: testTimeEvening)
    }

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
        self.displayName = d.string(forKey: "displayName") ?? ""
        self.yearOfBirth = d.string(forKey: "yearOfBirth") ?? ""
        self.testTimeMorning = d.string(forKey: "testTimeMorning") ?? "08:00-10:00"
        self.testTimeNoon = d.string(forKey: "testTimeNoon") ?? "12:00-14:00"
        self.testTimeEvening = d.string(forKey: "testTimeEvening") ?? "18:00-20:00"
        self.testTimeCustom = d.string(forKey: "testTimeCustom") ?? ""
        self.healthAppleStatus = d.string(forKey: "healthAppleStatus") ?? "skipped"
        self.healthStravaStatus = d.string(forKey: "healthStravaStatus") ?? "skipped"
        self.notificationsOptIn = d.object(forKey: "notificationsOptIn") as? Bool ?? false
        self.keyboardOptIn = d.object(forKey: "keyboardOptIn") as? Bool ?? false
        self.onboardingVersion = d.integer(forKey: "onboardingVersion")
        self.consentSignatureName = d.string(forKey: "consentSignatureName") ?? ""
        self.consentSignatureImage = d.string(forKey: "consentSignatureImage") ?? ""
        self.consentLocale = d.string(forKey: "consentLocale") ?? "en"

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
            UserProfile.saveToKeychain(uid)
        } else if let keychainId = UserProfile.getFromKeychain(), !keychainId.isEmpty {
            // Survived reinstall — restore into UserDefaults
            self.userId = keychainId
            d.set(keychainId, forKey: "userId")
        } else {
            let newId = "pd_" + UUID().uuidString.prefix(8).lowercased()
            self.userId = newId
            d.set(newId, forKey: "userId")
            UserProfile.saveToKeychain(newId)
        }
    }

    func clearAll() {
        ["consentGiven","profileComplete","userId","age","gender","dominantHand","affectedSide","medications",
         "hrDeviceIdentifier","hrDeviceName","beanieDeviceIdentifier","beanieDeviceName",
         "displayName","yearOfBirth","testTimeMorning","testTimeNoon","testTimeEvening","testTimeCustom",
         "healthAppleStatus","healthStravaStatus","notificationsOptIn","keyboardOptIn","onboardingVersion",
         "consentSignatureName","consentSignatureImage","consentLocale"]
            .forEach { UserDefaults.standard.removeObject(forKey: $0) }
        UserProfile.deleteFromKeychain()
        consentGiven = false
        profileComplete = false
        onboardingVersion = 0
        let newId = "pd_" + UUID().uuidString.prefix(8).lowercased()
        userId = newId
        age = ""; gender = ""; dominantHand = "Right"; affectedSide = "Left"; medications = []
        hrDeviceIdentifier = ""; hrDeviceName = ""
        beanieDeviceIdentifier = ""; beanieDeviceName = ""
        displayName = ""; yearOfBirth = ""
        testTimeMorning = "08:00-10:00"; testTimeNoon = "12:00-14:00"
        testTimeEvening = "18:00-20:00"; testTimeCustom = ""
        healthAppleStatus = "skipped"; healthStravaStatus = "skipped"
        notificationsOptIn = false; keyboardOptIn = false
        consentSignatureName = ""; consentSignatureImage = ""; consentLocale = "en"
    }

    private func save(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }

    // MARK: - Keychain (static — safe to call from init before self is fully initialized)
    // kSecAttrService scopes the item to this app's bundle so the generic
    // account key "participantUserId" cannot collide with any other app's Keychain entry.
    private static let keychainService = Bundle.main.bundleIdentifier ?? "com.oriw.pdcollect.ios1"
    private static let keychainAccount = "participantUserId"

    static func saveToKeychain(_ value: String) {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount
        ]
        let update: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    static func getFromKeychain() -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      keychainService,
            kSecAttrAccount:      keychainAccount,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let uid = String(data: data, encoding: .utf8),
              !uid.isEmpty else { return nil }
        return uid
    }

    static func deleteFromKeychain() {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount
        ]
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
            "affectedSide": affectedSide,
            "displayName": displayName,
            "yearOfBirth": yearOfBirth,
            "testTimeMorning": testTimeMorning,
            "testTimeNoon": testTimeNoon,
            "testTimeEvening": testTimeEvening,
            "testTimeCustom": testTimeCustom,
            "healthAppleStatus": healthAppleStatus,
            "healthStravaStatus": healthStravaStatus,
            "notificationsOptIn": notificationsOptIn,
            "keyboardOptIn": keyboardOptIn,
            "onboardingVersion": onboardingVersion,
            "consentSignatureName": consentSignatureName,
            "consentSignatureImage": consentSignatureImage,
            "consentLocale": consentLocale,
        ]
        
        let medsList = medications.map { ["name": $0.name, "dosage": $0.dosage] }
        map["medications"] = medsList
        
        return map
    }
    
    /// Local-wins merge used on sign-in.
    /// Fills in only fields that the local profile hasn't had a chance to set yet
    /// (i.e. the profile is not yet marked complete). Once the profile is complete
    /// we trust all local values absolutely and never overwrite them from cloud.
    func mergeFromCloud(from map: [String: Any]) {
        // Consent / completion flags: accept from cloud only if not yet set locally.
        if !consentGiven, let consent = map["consentGiven"] as? Bool { self.consentGiven = consent }
        if !profileComplete, let complete = map["profileComplete"] as? Bool { self.profileComplete = complete }

        // Demographic fields: only fill from cloud if the local profile is incomplete.
        // Using !profileComplete avoids the default-value trap: "Right" and "Left" are
        // valid user choices, not empty strings, so string equality can't distinguish
        // "user picked Right" from "never set".
        if !profileComplete {
            if age.isEmpty, let a = map["age"] as? String, !a.isEmpty { self.age = a }
            if gender.isEmpty, let g = map["gender"] as? String, !g.isEmpty { self.gender = g }
            if let hand = map["dominantHand"] as? String, !hand.isEmpty { self.dominantHand = hand }
            if let side = map["affectedSide"] as? String, !side.isEmpty { self.affectedSide = side }
            if medications.isEmpty, let medsArray = map["medications"] as? [[String: Any]] {
                self.medications = medsArray.compactMap { dict in
                    guard let name = dict["name"] as? String else { return nil }
                    let dosage = dict["dosage"] as? String ?? ""
                    return Medication(name: name, dosage: dosage)
                }
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
