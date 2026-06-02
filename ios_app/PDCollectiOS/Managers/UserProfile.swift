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

    init() {
        let d = UserDefaults.standard
        self.consentGiven = d.bool(forKey: "consentGiven")
        self.profileComplete = d.bool(forKey: "profileComplete")
        self.age = d.string(forKey: "age") ?? ""
        self.gender = d.string(forKey: "gender") ?? ""
        self.dominantHand = d.string(forKey: "dominantHand") ?? "Right"
        self.affectedSide = d.string(forKey: "affectedSide") ?? "Left"

        if let uid = d.string(forKey: "userId"), !uid.isEmpty {
            self.userId = uid
        } else {
            let newId = "pd_" + UUID().uuidString.prefix(8).lowercased()
            self.userId = String(newId)
            d.set(self.userId, forKey: "userId")
        }

        if let data = d.data(forKey: "medications"),
           let meds = try? JSONDecoder().decode([String].self, from: data) {
            self.medications = meds
        } else {
            self.medications = []
        }
    }

    func clearAll() {
        ["consentGiven","profileComplete","userId","age","gender","dominantHand","affectedSide","medications"]
            .forEach { UserDefaults.standard.removeObject(forKey: $0) }
        consentGiven = false
        profileComplete = false
        let newId = "pd_" + UUID().uuidString.prefix(8).lowercased()
        userId = newId
        age = ""; gender = ""; dominantHand = "Right"; affectedSide = "Left"; medications = []
    }

    private func save(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
