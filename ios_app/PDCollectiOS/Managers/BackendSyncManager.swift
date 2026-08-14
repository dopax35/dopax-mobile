import Foundation
import FirebaseAuth

enum EmailCodeStartResult {
    case sent(expiresAt: Date, resendAvailableAt: Date, resendCooldownSeconds: Int)
    case invalidRequest
    case tooManyRequests(retryAfterSeconds: Int)
    case emailDeliveryFailed
    case networkError
}

enum EmailCodeVerifyInvalidReason {
    case noActiveCode
    case expired
    case tooManyAttempts
    case mismatch

    init?(apiReason: String) {
        switch apiReason {
        case "no_active_code": self = .noActiveCode
        case "expired": self = .expired
        case "too_many_attempts": self = .tooManyAttempts
        case "mismatch": self = .mismatch
        default: return nil
        }
    }
}

enum EmailCodeVerifyResult {
    case success(customToken: String, firebaseUid: String)
    case invalidCode(reason: EmailCodeVerifyInvalidReason, attemptsRemaining: Int?)
    case signInUnavailable
    case networkError
}

/**
 * Additive dual-write client for the Postgres backend (§7.1 / Phase 3).
 * Firestore remains the primary write path while BOTH_ARCH is true — failures
 * here must never block local onboarding or Firestore sync.
 */
final class BackendSyncManager {
    static let shared = BackendSyncManager()

    private static let emailCodeEnabledKey = "dopaxEmailCodeEnabled"

    /// Override in Info.plist (`DopaxBackendBaseURL`) or UserDefaults for device testing.
    var baseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "dopaxBackendBaseURL"),
           let url = URL(string: override), !override.isEmpty {
            return url
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "DopaxBackendBaseURL") as? String,
           let url = URL(string: plist), !plist.isEmpty {
            return url
        }
        return URL(string: "http://127.0.0.1:8080")!
    }

    private let defaults = UserDefaults.standard
    private let tokenKey = "dopaxBackendAccessToken"
    private let revisionKey = "dopaxBackendProfileRevision"

    static var emailCodeEnabled: Bool {
        UserDefaults.standard.object(forKey: emailCodeEnabledKey) as? Bool ?? false
    }

    var accessToken: String? {
        get { defaults.string(forKey: tokenKey) }
        set { defaults.set(newValue, forKey: tokenKey) }
    }

    var knownRevision: Int {
        get {
            let v = defaults.integer(forKey: revisionKey)
            return v > 0 ? v : 1
        }
        set { defaults.set(newValue, forKey: revisionKey) }
    }

    func fetchEmailCodeConfig(completion: ((Bool) -> Void)? = nil) {
        request(method: "GET", path: "/v1/config", body: nil, authorized: false) { code, json in
            guard (200..<300).contains(code),
                  let auth = json["auth"] as? [String: Any],
                  let enabled = auth["emailCodeEnabled"] as? Bool else {
                completion?(false)
                return
            }
            self.defaults.set(enabled, forKey: Self.emailCodeEnabledKey)
            completion?(enabled)
        }
    }

    func requestEmailCode(email: String, completion: @escaping (EmailCodeStartResult) -> Void) {
        request(
            method: "POST",
            path: "/v1/auth/email/start",
            body: ["email": email],
            authorized: false
        ) { code, json in
            switch code {
            case 202:
                guard let expiresAt = Self.parseISO8601(json["expiresAt"]),
                      let resendAt = Self.parseISO8601(json["resendAvailableAt"]),
                      let cooldown = json["resendCooldownSeconds"] as? Int else {
                    completion(.networkError)
                    return
                }
                completion(.sent(
                    expiresAt: expiresAt,
                    resendAvailableAt: resendAt,
                    resendCooldownSeconds: cooldown
                ))
            case 400:
                completion(.invalidRequest)
            case 429:
                let retry = json["retryAfterSeconds"] as? Int ?? 60
                completion(.tooManyRequests(retryAfterSeconds: retry))
            case 502:
                completion(.emailDeliveryFailed)
            default:
                completion(.networkError)
            }
        }
    }

    func verifyEmailCode(email: String, code: String, completion: @escaping (EmailCodeVerifyResult) -> Void) {
        request(
            method: "POST",
            path: "/v1/auth/email/verify",
            body: ["email": email, "code": code],
            authorized: false
        ) { status, json in
            switch status {
            case 200:
                guard let token = json["customToken"] as? String,
                      let uid = json["firebaseUid"] as? String else {
                    completion(.networkError)
                    return
                }
                completion(.success(customToken: token, firebaseUid: uid))
            case 401:
                let reasonRaw = json["reason"] as? String ?? "mismatch"
                let reason = EmailCodeVerifyInvalidReason(apiReason: reasonRaw) ?? .mismatch
                let remaining = json["attemptsRemaining"] as? Int
                completion(.invalidCode(reason: reason, attemptsRemaining: remaining))
            case 503:
                completion(.signInUnavailable)
            default:
                completion(.networkError)
            }
        }
    }

    func ensureSession(preferredParticipantCode: String, completion: ((Bool) -> Void)? = nil) {
        guard let user = Auth.auth().currentUser else {
            completion?(false)
            return
        }

        user.getIDToken { [weak self] idToken, error in
            guard let self, let idToken, error == nil else {
                completion?(false)
                return
            }

            var body: [String: Any] = [
                "idToken": idToken,
                "preferredParticipantCode": preferredParticipantCode,
            ]
            if let name = user.displayName { body["displayName"] = name }

            self.request(method: "POST", path: "/v1/auth/session", body: body, authorized: false) { code, json in
                guard (200..<300).contains(code) else {
                    completion?(false)
                    return
                }
                if let token = json["token"] as? String {
                    self.accessToken = token
                }
                if let profile = json["profile"] as? [String: Any],
                   let revision = profile["revision"] as? Int {
                    self.knownRevision = revision
                }
                completion?(true)
            }
        }
    }

    func syncConsent(
        signatureName: String,
        signatureImage: String? = nil,
        documentLocale: String? = nil,
        platform: String = "ios",
        completion: ((Bool) -> Void)? = nil
    ) {
        let code = UserProfile().userId
        ensureSession(preferredParticipantCode: code) { [weak self] ok in
            guard let self, ok else { completion?(false); return }
            var body: [String: Any] = [
                "signatureName": signatureName.isEmpty ? "participant" : signatureName,
                "documentVersion": "onboarding-v2",
                "platform": platform,
            ]
            if let signatureImage, !signatureImage.isEmpty {
                body["signatureImage"] = signatureImage
            }
            if let documentLocale, !documentLocale.isEmpty {
                body["documentLocale"] = documentLocale
            }
            self.request(
                method: "POST",
                path: "/v1/participants/me/consent",
                body: body,
                authorized: true
            ) { status, _ in
                completion?((200..<300).contains(status))
            }
        }
    }

    func syncProfile(_ profile: UserProfile, completion: ((Bool) -> Void)? = nil) {
        ensureSession(preferredParticipantCode: profile.userId) { [weak self] ok in
            guard let self, ok else { completion?(false); return }

            var body: [String: Any] = [
                "revision": self.knownRevision,
                "gender": profile.gender,
                "dominantHand": profile.dominantHand,
                "affectedSide": profile.affectedSide,
                "medications": profile.medications.map { ["name": $0.name, "dosage": $0.dosage] },
                "profileComplete": profile.profileComplete,
                "onboardingVersion": 2,
                "sessionWindows": [
                    "morning": profile.testTimeMorning,
                    "noon": profile.testTimeNoon,
                    "evening": profile.testTimeEvening,
                    "custom": profile.testTimeCustom,
                ],
                "healthConnections": [
                    "appleHealth": profile.healthAppleStatus,
                    "strava": profile.healthStravaStatus,
                ],
                "permissions": [
                    "notifications": profile.notificationsOptIn,
                    "keyboard": profile.keyboardOptIn,
                ],
            ]
            if let ageInt = Int(profile.age) {
                body["age"] = ageInt
            } else if !profile.age.isEmpty {
                body["age"] = profile.age
            }
            if !profile.displayName.isEmpty {
                body["signatureName"] = profile.displayName
                body["displayName"] = profile.displayName
            }
            if let yob = Int(profile.yearOfBirth) {
                body["yearOfBirth"] = yob
            }

            self.request(method: "PUT", path: "/v1/participants/me/profile", body: body, authorized: true) { status, json in
                if (200..<300).contains(status) {
                    if let profileJson = json["profile"] as? [String: Any],
                       let revision = profileJson["revision"] as? Int {
                        self.knownRevision = revision
                    }
                    completion?(true)
                    return
                }
                if status == 409,
                   let profileJson = json["profile"] as? [String: Any],
                   let revision = profileJson["revision"] as? Int {
                    self.knownRevision = revision
                }
                completion?(false)
            }
        }
    }

    private static func parseISO8601(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private func request(
        method: String,
        path: String,
        body: [String: Any]?,
        authorized: Bool,
        completion: @escaping (Int, [String: Any]) -> Void
    ) {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            completion(0, [:])
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authorized, let token = accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        req.timeoutInterval = 15

        URLSession.shared.dataTask(with: req) { data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any] ?? [:]
            DispatchQueue.main.async {
                completion(code, json)
            }
        }.resume()
    }
}
