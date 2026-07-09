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
    /// User-facing reason the last connect attempt failed — nil while idle
    /// or after a successful connect. Previously every failure path here
    /// (bad credentials, network error, Strava denying the request) failed
    /// completely silently: the button just sat there still saying "Connect
    /// Strava" with no explanation, which is what a "Strava login error"
    /// report with no specifics usually means in practice.
    @Published private(set) var connectionError: String?

    private override init() {
        isConnected = UserDefaults.standard.string(forKey: "strava_refresh_token") != nil
        super.init()
    }

    @MainActor
    func startAuth() {
        connectionError = nil

        // Fail fast with a clear message rather than round-tripping to
        // Strava's servers and showing whatever cryptic page/JSON they
        // return for an unregistered client_id.
        guard clientId != "REPLACE_WITH_STRAVA_CLIENT_ID", !clientId.isEmpty else {
            connectionError = "Strava isn't set up in this build yet (no API credentials configured). A developer needs to register the app at strava.com/settings/api first."
            return
        }

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
            guard let self else { return }

            // The user tapping "Cancel" on the sign-in sheet is an
            // intentional, expected action — not a failure to report.
            if let authError = error as? ASWebAuthenticationSessionError,
               authError.code == .canceledLogin {
                return
            }
            guard error == nil else {
                DispatchQueue.main.async { self.connectionError = "Strava sign-in didn't complete. Please try again." }
                return
            }
            guard let callbackURL,
                  let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems else {
                DispatchQueue.main.async { self.connectionError = "Strava sign-in didn't complete. Please try again." }
                return
            }
            // Strava redirects with "?error=access_denied" (among other
            // values) when the user declines on Strava's own consent
            // screen, rather than dismissing the sheet outright.
            if let deniedReason = items.first(where: { $0.name == "error" })?.value {
                DispatchQueue.main.async {
                    self.connectionError = deniedReason == "access_denied"
                        ? "Strava access wasn't granted."
                        : "Strava sign-in failed (\(deniedReason))."
                }
                return
            }
            guard let code = items.first(where: { $0.name == "code" })?.value else {
                DispatchQueue.main.async { self.connectionError = "Strava didn't return an authorization code. Please try again." }
                return
            }
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
            await MainActor.run { connectionError = "Couldn't reach Strava. Check your connection and try again." }
        }
    }

    /// Parses Strava's token-exchange response. A successful exchange has
    /// both access_token and refresh_token; anything else is an error, even
    /// though the HTTP call itself "succeeded" — Strava returns its error
    /// details as a 200-range-adjacent JSON body like
    /// {"message":"Bad Request","errors":[{"resource":"Application","field":"client_id","code":"invalid"}]},
    /// not a thrown exception, so this used to silently do nothing at all
    /// (isConnected stayed false with zero explanation) whenever the
    /// exchange failed for any reason, including the placeholder
    /// clientId/clientSecret still being in place.
    private func saveTokens(from data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            DispatchQueue.main.async { self.connectionError = "Strava returned an unexpected response. Please try again." }
            return
        }
        guard json["access_token"] != nil, json["refresh_token"] != nil else {
            let firstError = (json["errors"] as? [[String: Any]])?.first
            let fieldDetail = [firstError?["field"] as? String, firstError?["code"] as? String]
                .compactMap { $0 }.joined(separator: " ")
            let message = (json["message"] as? String) ?? "Strava sign-in failed."
            DispatchQueue.main.async {
                self.connectionError = fieldDetail.isEmpty ? message : "\(message) (\(fieldDetail))"
            }
            return
        }
        UserDefaults.standard.set(json["access_token"] as? String, forKey: "strava_access_token")
        UserDefaults.standard.set(json["refresh_token"] as? String, forKey: "strava_refresh_token")
        UserDefaults.standard.set(json["expires_at"] as? Int, forKey: "strava_expires_at")
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = true
            self?.connectionError = nil
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
