import Foundation
import FirebaseAuth
import FirebaseFirestore

class FirebaseSyncManager {
    static let shared = FirebaseSyncManager()
    private let db = Firestore.firestore()
    
    func saveProfileToCloud(profile: UserProfile, completion: ((Bool) -> Void)? = nil) {
        guard let user = Auth.auth().currentUser else {
            completion?(false)
            return
        }
        
        var data = profile.toMap()
        data["email"] = user.email ?? ""
        data["lastSyncTime"] = Int64(Date().timeIntervalSince1970 * 1000)
        
        db.collection("users").document(user.uid).setData(data) { error in
            if let error = error {
                print("Error saving profile to cloud: \(error)")
                completion?(false)
            } else {
                completion?(true)
            }
        }
    }
    
    func loadProfileFromCloud(profile: UserProfile, completion: @escaping (Bool) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }
        
        db.collection("users").document(uid).getDocument { document, error in
            if let document = document, document.exists, let data = document.data() {
                DispatchQueue.main.async {
                    profile.update(from: data)
                    completion(true)
                }
            } else {
                print("Profile does not exist or error: \(error?.localizedDescription ?? "Unknown error")")
                completion(false)
            }
        }
    }
}
