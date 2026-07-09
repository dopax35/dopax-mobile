import Foundation
import AuthenticationServices
import UIKit

/// Strava OAuth2 (authorization-code) connect flow + recent-activity fetch.
///
/// SETUP REQUIRED before this works (programmer action, not done by this code):
///  1. Register a free app at https://www.strava.com/settings/api to get a
///     Client ID + Client Secret. Fill both into clientId / clientSecret below.
///  2. Set "Authorization Callback Domain" in that Strava app's settings to
///     exactly "strava-callback" — Strava requires redirect_uri to be
///     "<scheme>://<callback_domain>", matching the "pdcollect" URL scheme
///     that needs to be added to Info.plist's CFBundleURLTypes (alongside the
///     existing Google Sign-In scheme already there).
///  3. Strava's OAuth is not fully spec-compliant for native custom-scheme
///     redirects — test on a real device; you may need to adjust the exact
///     redirect_uri format if Strava returns "invalid redirect_uri".
///
/// SECURITY NOTE: embedding clientSecret in the app binary means it can be
/// extracted from the IPA. Consider moving the token exchange into a Firebase
/// Cloud Function (this app already uses Firebase) so the secret never ships
/// to devices — this file keeps it client-side to stay a drop-in starting point.
final class StravaManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = StravaManager()

    private let clientId = "REPLACE_WITH_STRAVA_CLIENT_ID"
    private let clientSecret = "REPLACE_WITH_STRAVA_CLIENT_SECRET"
    private let redirectURI = "pdcollect://strava-callback"

    private var authSession: ASWebAuthenticationSession?

    /// @Published (rather than a plain UserDefaults read) so SwiftUI views
    /// update their "Connect Strava" / "Import from Strava" button label the
    /// moment the OAuth callback completes, with no polling needed.
    @Published private(set) var isConnected: Bool

    private override init() {
        isConnected = UserDefaults.standard.string(forKey: "strava_refresh_token") != nil
        super.init()
    }

    @MainActor
    func startAuth() {
        var components = URLComponents(string: "https://www.strava.com/oauth/mobile/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: "activity:read_all")
        ]
        guard let url = components.url else { return }

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "pdcollect") { [weak self] callbackURL, error in
            guard let self, let callbackURL, error == nil,
                  let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                      .queryItems?.first(where: { $0.name == "code" })?.value else { return }
            Task { await self.exchangeCodeForToken(code) }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.authSession = session
        session.start()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }

    private func exchangeCodeForToken(_ code: String) async {
        var request = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "client_id=\(clientId)&client_secret=\(clientSecret)&code=\(code)&grant_type=authorization_code"
            .data(using: .utf8)
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            saveTokens(from: data)
        } catch {
            // best-effort; user can retry Connect Strava
        }
    }

    private func saveTokens(from data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        UserDefaults.standard.set(json["access_token"] as? String, forKey: "strava_access_token")
        UserDefaults.standard.set(json["refresh_token"] as? String, forKey: "strava_refresh_token")
        UserDefaults.standard.set(json["expires_at"] as? Int, forKey: "strava_expires_at")
        let nowConnected = json["refresh_token"] != nil
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = nowConnected
        }
    }

    private func ensureFreshAccessToken() async -> String? {
        guard let refreshToken = UserDefaults.standard.string(forKey: "strava_refresh_token") else { return nil }
        let expiresAt = UserDefaults.standard.integer(forKey: "strava_expires_at")
        if let access = UserDefaults.standard.string(forKey: "strava_access_token"),
           Int(Date().timeIntervalSince1970) < expiresAt - 60 {
            return access
        }

        var request = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "client_id=\(clientId)&client_secret=\(clientSecret)&grant_type=refresh_token&refresh_token=\(refreshToken)"
            .data(using: .utf8)
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            saveTokens(from: data)
            return UserDefaults.standard.string(forKey: "strava_access_token")
        } catch {
            return nil
        }
    }

    /// Fetches activities from the last [days] days and maps them onto this
    /// app's physical-activity schema.
    func fetchRecentActivities(days: Int = 7) async -> [PhysicalActivityEvent] {
        guard let token = await ensureFreshAccessToken() else { return [] }
        let after = Int(Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970)
        guard let url = URL(string: "https://www.strava.com/api/v3/athlete/activities?after=\(after)&per_page=50") else { return [] }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
            let isoFormatter = ISO8601DateFormatter()
            return arr.compactMap { a -> PhysicalActivityEvent? in
                guard let startStr = a["start_date"] as? String,
                      let startDate = isoFormatter.date(from: startStr) else { return nil }
                let type = a["type"] as? String ?? ""
                let movingTime = a["moving_time"] as? Int ?? 0
                let kj = a["kilojoules"] as? Double
                let hr = a["average_heartrate"] as? Double
                // Strava's numeric activity id, stringified for import
                // dedup via NSNumber so it doesn't matter how JSONSerialization
                // happened to box this particular number internally.
                let activityId = (a["id"] as? NSNumber)?.stringValue ?? ""
                return PhysicalActivityEvent(
                    timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
                    activityType: PhysicalActivityEvent.mapExternalType(type),
                    timeOfDayMs: Int64(startDate.timeIntervalSince1970 * 1000),
                    source: "Strava",
                    durationMin: Double(movingTime) / 60.0,
                    calories: kj.map { $0 * 0.239006 }, // kJ -> kcal
                    avgHeartRate: hr,
                    externalId: activityId
                )
            }
        } catch {
            return []
        }
    }
}
