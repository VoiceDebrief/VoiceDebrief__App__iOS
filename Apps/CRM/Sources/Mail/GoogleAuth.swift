import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import UIKit

/// Signing in to Google from the app (OAuth 2.0 for installed apps, with PKCE): the person signs in on
/// Google's own page in a system sheet, the app gets a code, swaps it for tokens, and keeps the refresh
/// token in this device's Keychain. The client is an iOS OAuth client the owner makes in Google Cloud for
/// the bundle `ai.sgit.crm.app`; its id is not a secret and is entered in the app (pasted or scanned), so
/// nothing is built in. No client secret exists for an iOS client, and none is in the app.
@MainActor
@Observable
final class GoogleAuth: NSObject {
    enum Problem: LocalizedError, Equatable {
        case noClient, cancelled, refused(String), noAccount

        var errorDescription: String? {
            switch self {
            case .noClient: return "Enter the Google client id first (an iOS OAuth client for ai.sgit.crm.app)."
            case .cancelled: return "Sign-in was cancelled."
            case .refused(let why): return "Google said no: \(why)"
            case .noAccount: return "Not signed in to Gmail."
            }
        }
    }

    /// Read the inbox and send as the person; nothing else.
    nonisolated static let scopes = ["https://www.googleapis.com/auth/gmail.readonly", "https://www.googleapis.com/auth/gmail.send"]
    nonisolated static let clientKey = "crm.google.clientID"
    nonisolated static let refreshName = "google-refresh-token"

    private let store: any SecretStore
    private let defaults: UserDefaults
    private(set) var clientID: String
    private(set) var account: String?
    private(set) var signingIn = false
    private var accessToken: String?
    private var expiry = Date.distantPast
    private var session: ASWebAuthenticationSession?
    /// Whether a refresh token is kept on this device (stored, so views follow it).
    private(set) var signedIn = false

    init(store: any SecretStore = KeychainStore(), defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        clientID = defaults.string(forKey: Self.clientKey) ?? ""
        account = defaults.string(forKey: "crm.google.account")
        super.init()
        signedIn = store.get(Self.refreshName) != nil
    }

    var hasClient: Bool { !clientID.isEmpty }

    /// Accepts the client id as Google shows it (`<number>-<letters>.apps.googleusercontent.com`), or its reversed form.
    func setClient(_ text: String) {
        var id = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.hasPrefix("com.googleusercontent.apps.") {
            id = String(id.dropFirst("com.googleusercontent.apps.".count)) + ".apps.googleusercontent.com"
        }
        clientID = id
        defaults.set(id, forKey: Self.clientKey)
    }

    /// The custom scheme Google redirects an iOS client to: the client id reversed.
    nonisolated static func redirectScheme(for clientID: String) -> String {
        "com.googleusercontent.apps." + clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }

    nonisolated static func redirectURI(for clientID: String) -> String { redirectScheme(for: clientID) + ":/oauth2redirect" }

    // MARK: PKCE (RFC 7636)

    nonisolated static func verifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    nonisolated static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    nonisolated static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    nonisolated static func authorizeURL(clientID: String, challenge: String, state: String) -> URL {
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI(for: clientID)),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return c.url!
    }

    // MARK: Signing in and out

    func signIn() async throws {
        guard hasClient else { throw Problem.noClient }
        signingIn = true
        defer { signingIn = false }
        let verifier = Self.verifier()
        let state = UUID().uuidString
        let url = Self.authorizeURL(clientID: clientID, challenge: Self.challenge(for: verifier), state: state)
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.redirectScheme(for: clientID)) { url, error in
                if let url { continuation.resume(returning: url) }
                else if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin { continuation.resume(throwing: Problem.cancelled) }
                else { continuation.resume(throwing: error ?? Problem.cancelled) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
        session = nil
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { throw Problem.refused("the reply did not match this sign-in") }
        if let error = items.first(where: { $0.name == "error" })?.value { throw Problem.refused(error) }
        guard let code = items.first(where: { $0.name == "code" })?.value else { throw Problem.refused("no code") }
        try await exchange(["code": code, "code_verifier": verifier, "grant_type": "authorization_code",
                            "redirect_uri": Self.redirectURI(for: clientID)])
    }

    /// Forgets the tokens on this device and asks Google to revoke them.
    func signOut() async {
        if let token = store.get(Self.refreshName).flatMap({ String(data: $0, encoding: .utf8) }) {
            var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.form(["token": token])
            _ = try? await URLSession.shared.data(for: request)
        }
        store.set(Self.refreshName, nil)
        signedIn = false
        accessToken = nil
        expiry = .distantPast
        account = nil
        defaults.removeObject(forKey: "crm.google.account")
    }

    func setAccount(_ address: String) {
        account = address
        defaults.set(address, forKey: "crm.google.account")
    }

    /// A current access token, refreshed when it has expired.
    func token() async throws -> String {
        if let accessToken, expiry > Date().addingTimeInterval(60) { return accessToken }
        guard let refresh = store.get(Self.refreshName).flatMap({ String(data: $0, encoding: .utf8) }) else { throw Problem.noAccount }
        try await exchange(["refresh_token": refresh, "grant_type": "refresh_token"])
        guard let accessToken else { throw Problem.noAccount }
        return accessToken
    }

    private func exchange(_ fields: [String: String]) async throws {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(fields.merging(["client_id": clientID]) { a, _ in a })
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200, let access = json["access_token"] as? String else {
            if fields["grant_type"] == "refresh_token", json["error"] as? String == "invalid_grant" {
                store.set(Self.refreshName, nil)
                signedIn = false
            }
            throw Problem.refused((json["error_description"] as? String) ?? (json["error"] as? String) ?? "status \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        accessToken = access
        expiry = Date().addingTimeInterval(TimeInterval((json["expires_in"] as? Int) ?? 3000))
        if let refresh = json["refresh_token"] as? String {
            store.set(Self.refreshName, Data(refresh.utf8))
            signedIn = true
        }
    }

    nonisolated static func form(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return Data(fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").utf8)
    }
}

extension GoogleAuth: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
