import Foundation
import Combine

class UserProfile: ObservableObject {
    @Published var consentGiven: Bool      { didSet { save("consentGiven", consentGiven) } }
    @Published var profileComplete: Bool   { didSet { save("profileComplete", profileComplete) } }
    @Published var userId: String          { didSet { save("userId", userId) } }
    @Published var age: String             { didSet { save("age", age) } }
    @Published var gender: String          { didSet { save("gender", gender) } }
    @Published var dominantHand: String    { didSet { save("dominantHand", dominantHand) } }
    @Published var affectedSide: String    { didSet { save("affectedSide", affectedSide) } }
    @Published var medications: [String] {
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

        if let data = d.data(forKey: "medications"),
           let meds = try? JSONDecoder().decode([String].self, from: data) {
            self.medications = meds
        } else {
            self.medications = []
        }

        if let uid = d.string(forKey: "userId"), !uid.isEmpty {
            self.userId = uid
        } else {
            let newId = "pd_" + UUID().uuidString.prefix(8).lowercased()
            self.userId = newId
            d.set(newId, forKey: "userId")
        }
    }

    func clearAll() {
        ["consentGiven","profileComplete","userId","age","gender","dominantHand","affectedSide","medications",
         "hrDeviceIdentifier","hrDeviceName","beanieDeviceIdentifier","beanieDeviceName"]
            .forEach { UserDefaults.standard.removeObject(forKey: $0) }
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
}
