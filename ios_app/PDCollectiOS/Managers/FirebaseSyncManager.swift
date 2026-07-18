import Foundation
import FirebaseAuth
import FirebaseFirestore

class FirebaseSyncManager {
    static let shared = FirebaseSyncManager()
    private let db = Firestore.firestore()

    // MARK: - Save (full overwrite)

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
                print("[FirebaseSyncManager] Error saving profile: \(error)")
                completion?(false)
            } else {
                completion?(true)
            }
        }
    }

    // MARK: - Load (full overwrite of local)

    /// Fetches the cloud document and **fully overwrites** the local profile.
    /// Only use this when you are certain the cloud copy is authoritative
    /// (e.g. user explicitly taps "Restore from cloud").
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
                print("[FirebaseSyncManager] No cloud profile or error: \(error?.localizedDescription ?? "Unknown")")
                completion(false)
            }
        }
    }

    // MARK: - Safe sign-in sync (local-wins merge)

    /// Called immediately after the user signs in (Google or Apple).
    ///
    /// Strategy:
    /// - If a Firestore document **exists** for this Firebase UID → merge it into
    ///   the local profile using local-wins semantics (`mergeFromCloud`). Local
    ///   data is preserved; only empty/missing fields are filled from the cloud.
    ///   Then save the merged result back so the cloud is up-to-date.
    /// - If **no** Firestore document exists (first time this account is linked, or
    ///   the user never synced before) → publish the existing local profile to the
    ///   cloud immediately, preserving the participant's userId and all their data.
    ///
    /// This means an existing user who updates the app and is forced to re-auth
    /// will never see a blank profile: their local data is kept and pushed to cloud.
    func syncProfileOnSignIn(profile: UserProfile, completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(false)
            return
        }

        db.collection("users").document(user.uid).getDocument { [weak self] document, error in
            // If self was deallocated (e.g. app backgrounded before Firestore responded)
            // still call completion so the caller (LoginView) isn't left in a loading state.
            guard let self else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            if let document = document, document.exists, let data = document.data() {
                // Cloud profile found — merge (local data wins).
                DispatchQueue.main.async {
                    profile.mergeFromCloud(from: data)
                    // Push merged result back to cloud to keep everything in sync.
                    self.saveProfileToCloud(profile: profile)
                    completion(true)
                }
            } else {
                // No cloud profile yet — upload local data so it's backed up.
                print("[FirebaseSyncManager] No cloud profile found for UID \(user.uid) — uploading local profile.")
                DispatchQueue.main.async {
                    self.saveProfileToCloud(profile: profile) { success in
                        completion(success)
                    }
                }
            }
        }
    }
}
