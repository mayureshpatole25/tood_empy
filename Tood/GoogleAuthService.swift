import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import Observation

/// Direct Google OAuth (not EventKit/Calendar.app) — most people's Google
/// accounts aren't hooked into macOS's Calendar app, so going straight to
/// Google's own API is the only way this reliably sees their events.
///
/// Standard installed-app flow: `ASWebAuthenticationSession` presents
/// Google's sign-in as a native auth sheet and captures the redirect via
/// the app's own URL scheme (`today-app://oauth-callback`, registered in
/// Info.plist) — no custom URL-handling code needed, the session captures
/// it itself. PKCE (code_verifier/code_challenge) protects the auth code
/// in transit even though this client type also has a client_secret; per
/// Google's own docs, a "Desktop app" client's secret isn't meant to be
/// kept truly confidential (it can't be, in a distributable binary), so
/// embedding it here is the sanctioned pattern for this client type — PKCE
/// is the real protection.
///
/// Only the refresh token is sensitive long-term; it lives in the Keychain
/// (`KeychainStore`), never UserDefaults/disk.
@MainActor
@Observable
final class GoogleAuthService: NSObject {
    static let shared = GoogleAuthService()

    private let clientID = GoogleOAuthSecrets.clientID
    private let clientSecret = GoogleOAuthSecrets.clientSecret
    // Google's "Desktop app" OAuth clients only accept a loopback redirect
    // or a custom scheme in this exact reverse-client-id form — an
    // arbitrary scheme like the "today-app://" this started as gets
    // rejected outright with "Access blocked: Authorization Error".
    private let urlScheme = "com.googleusercontent.apps.1066136870078-ebftr2rvhk0umkp7m5uqap3t46fa86ff"
    private var redirectURI: String { "\(urlScheme):/oauth2redirect" }
    private let scope = "https://www.googleapis.com/auth/calendar.readonly"

    private(set) var isConnected: Bool
    private(set) var connectedEmail: String?

    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private var accessTokenExpiry: Date?
    @ObservationIgnored private var currentSession: ASWebAuthenticationSession?

    private enum Keys {
        static let refreshToken = "today.google.refreshToken"
        static let email = "today.google.email"
    }

    private var refreshToken: String? {
        get { KeychainStore.read(key: Keys.refreshToken) }
        set {
            if let newValue {
                KeychainStore.write(key: Keys.refreshToken, value: newValue)
            } else {
                KeychainStore.delete(key: Keys.refreshToken)
            }
        }
    }

    override init() {
        isConnected = KeychainStore.read(key: Keys.refreshToken) != nil
        connectedEmail = UserDefaults.standard.string(forKey: Keys.email)
        super.init()
    }

    // MARK: - Connect / disconnect

    func connect() async throws {
        let verifier = Self.randomCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let state = UUID().uuidString

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: components.url!, callbackURLScheme: urlScheme
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? AuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            // Keeps the user's existing Google sign-in session (most people
            // are already signed in somewhere) instead of forcing a fresh
            // login every time.
            session.prefersEphemeralWebBrowserSession = false
            currentSession = session
            session.start()
        }

        let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        guard callbackComponents?.queryItems?.first(where: { $0.name == "state" })?.value == state else {
            throw AuthError.stateMismatch
        }
        guard let code = callbackComponents?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.missingCode
        }

        try await exchangeCodeForTokens(code: code, verifier: verifier)
    }

    func disconnect() {
        refreshToken = nil
        accessToken = nil
        accessTokenExpiry = nil
        connectedEmail = nil
        UserDefaults.standard.removeObject(forKey: Keys.email)
        isConnected = false
    }

    // MARK: - Tokens

    /// A valid access token, refreshing it first if it's expired or about
    /// to be. Everything that calls the Calendar API should go through
    /// this rather than touching `accessToken` directly.
    func validAccessToken() async throws -> String {
        if let accessToken, let accessTokenExpiry, accessTokenExpiry > Date() {
            return accessToken
        }
        guard let refreshToken else { throw AuthError.notConnected }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode([
            "client_id": clientID,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ]).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 400 || http.statusCode == 401 {
            // Refresh token revoked/expired at Google's end — only real fix
            // is signing in again.
            disconnect()
            throw AuthError.notConnected
        }
        try Self.checkOK(response, data)

        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = token.accessToken
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(token.expiresIn - 60))
        return token.accessToken
    }

    private func exchangeCodeForTokens(code: String, verifier: String) async throws {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode([
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ]).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkOK(response, data)
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)

        accessToken = token.accessToken
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(token.expiresIn - 60))
        if let newRefreshToken = token.refreshToken { refreshToken = newRefreshToken }
        isConnected = true

        try? await fetchAndStoreEmail()
    }

    private func fetchAndStoreEmail() async throws {
        guard let accessToken else { return }
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        if let info = try? JSONDecoder().decode(UserInfo.self, from: data) {
            connectedEmail = info.email
            UserDefaults.standard.set(info.email, forKey: Keys.email)
        }
    }

    // MARK: - PKCE

    private static func randomCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString()
    }

    // MARK: - Helpers

    private static func formEncode(_ params: [String: String]) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return params.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
    }

    private static func checkOK(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AuthError.requestFailed(String(data: data, encoding: .utf8) ?? "unknown error")
        }
    }

    enum AuthError: LocalizedError {
        case cancelled, stateMismatch, missingCode, notConnected, requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .cancelled: return "Sign-in was cancelled."
            case .stateMismatch: return "Sign-in response didn't match the request."
            case .missingCode: return "Google didn't return an authorization code."
            case .notConnected: return "Not connected to Google Calendar."
            case .requestFailed(let body): return "Google request failed: \(body)"
            }
        }
    }
}

extension GoogleAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

private struct UserInfo: Decodable {
    let email: String
}

private extension Data {
    /// Base64url, no padding — what PKCE and the code verifier/challenge require.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
