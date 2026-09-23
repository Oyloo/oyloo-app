import AuthenticationServices
import CryptoKit
import Foundation

/// Browser sign-in against an OAuth 2.1 server, so every person on the device
/// uses their own account instead of sharing one static token.
///
/// The client registers itself dynamically (RFC 7591) on first sign-in: a
/// native app cannot keep a secret, so it registers as a public client and
/// proves possession of the request with PKCE instead. Nothing about any
/// particular server lives in this repo — the base URL comes from settings.
public enum OAuthClient {
    public enum Failure: LocalizedError {
        case notConfigured
        case discovery(String)
        case registration(String)
        case authorization(String)
        case token(String)
        case notSignedIn

        /// The case, with nothing of the server's answer in it.
        ///
        /// The description below carries the server's own words — for a token
        /// failure, its response body verbatim — which is the user's and is
        /// not for a public log or an exported attribute. This is what those
        /// get instead.
        public var kind: String {
            switch self {
            case .notConfigured: "notConfigured"
            case .discovery: "discovery"
            case .registration: "registration"
            case .authorization: "authorization"
            case .token: "token"
            case .notSignedIn: "notSignedIn"
            }
        }

        public var errorDescription: String? {
            switch self {
            case .notConfigured: "Set the server address first."
            case .discovery(let m): "Server discovery failed: \(m)"
            case .registration(let m): "Client registration failed: \(m)"
            case .authorization(let m): "Sign-in failed: \(m)"
            case .token(let m): "Token exchange failed: \(m)"
            case .notSignedIn: "Not signed in."
            }
        }
    }

    /// The scheme must also be declared in the app's Info.plist, otherwise the
    /// callback never reaches the session. RFC 8252 §7.1: a private-use scheme
    /// is the reverse-DNS name of a domain the app's author controls, with a
    /// single slash after it; the server only registers schemes under our
    /// domain, so a bare word like "oyloo" would be refused.
    public static let callbackScheme = "com.oyloo.life"
    private static let redirectURI = "com.oyloo.life:/oauth"

    // MARK: - Public API

    public static var isSignedIn: Bool {
        guard SyncSettings.isConfigured else { return false }
        return TokenStore.load(for: SyncSettings.baseURL) != nil
    }

    /// Drops the tokens locally and asks the server to forget them too: a
    /// refresh token that outlives sign-out is a bearer secret nobody is
    /// watching. The revoke call is best effort; the keychain is cleared
    /// regardless, and so is the remembered client, so the next sign-in
    /// starts from a clean registration.
    public static func signOut() {
        let base = SyncSettings.baseURL
        let stored = TokenStore.load(for: base)
        // Personal devices, but the next account must never see the last
        // one's money or tasks, even for the moment before a refresh.
        ResponseCache.forServer(base).clear()
        TokenStore.clear(for: base)
        forgetClient()
        guard let stored, let url = URL(string: base) else { return }
        Task.detached {
            await revoke(token: stored.refreshToken ?? stored.accessToken, clientID: stored.clientID, base: url)
        }
    }

    /// Runs the whole dance: discovery, registration, browser consent, token
    /// exchange. Presents from `anchor` because iOS requires a window.
    @MainActor
    public static func signIn(anchor: ASPresentationAnchor?) async throws {
        guard SyncSettings.isConfigured, let base = URL(string: SyncSettings.baseURL) else {
            throw Failure.notConfigured
        }
        let metadata = try await discover(base: base)
        let clientID = try await registerClient(metadata: metadata)

        let verifier = randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        let state = randomString(16)

        var authComponents = URLComponents(url: metadata.authorization, resolvingAgainstBaseURL: false)
        authComponents?.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: "openid profile email offline_access"),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256")
        ]
        guard let authURL = authComponents?.url else { throw Failure.authorization("bad URL") }

        // A cancelled sheet keeps the registration: every re-registration is
        // a new anonymous row on the server, so the client is forgotten only
        // when the server itself objects to it (an OAuth error in the
        // callback, or a rejected token exchange), not on cancel or a flaky
        // network. A client the server no longer knows is also recoverable
        // through Sign out, which forgets it too.
        let callback = try await present(authURL: authURL, anchor: anchor)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let err = items.first(where: { $0.name == "error" })?.value {
            forgetClient()
            throw Failure.authorization(err)
        }
        guard items.first(where: { $0.name == "state" })?.value == state else {
            throw Failure.authorization("state mismatch")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw Failure.authorization("no code")
        }

        let tokens: TokenStore.Tokens
        do {
            tokens = try await exchange(
                code: code, verifier: verifier, clientID: clientID, endpoint: metadata.token
            )
        } catch let failure as Failure {
            forgetClient()
            throw failure
        }
        TokenStore.save(tokens, for: SyncSettings.baseURL)
    }

    private static func forgetClient() {
        SharedDefaults.set(nil as String?, forKey: clientIDKey(for: SyncSettings.baseURL))
    }

    /// A token good for the next call, refreshed when it is about to expire.
    public static func validAccessToken() async throws -> String {
        guard SyncSettings.isConfigured, let base = URL(string: SyncSettings.baseURL) else {
            throw Failure.notConfigured
        }
        guard let stored = TokenStore.load(for: SyncSettings.baseURL) else {
            throw Failure.notSignedIn
        }
        if stored.isFresh { return stored.accessToken }
        guard let refresh = stored.refreshToken else { throw Failure.notSignedIn }

        let metadata = try await discover(base: base)
        var request = URLRequest(url: metadata.token)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form([
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": stored.clientID
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard ok(response) else {
            // A refresh token the server no longer accepts means the session
            // is over: drop it so the UI offers a fresh sign-in instead of
            // failing silently on every upload. The remembered client goes
            // too, in case the refusal was the server having forgotten it.
            TokenStore.clear(for: SyncSettings.baseURL)
            forgetClient()
            throw Failure.token(body(data))
        }
        var tokens = try decodeTokens(data, clientID: stored.clientID)
        if tokens.refreshToken == nil { tokens.refreshToken = refresh }
        TokenStore.save(tokens, for: SyncSettings.baseURL)
        return tokens.accessToken
    }

    // MARK: - Steps

    private struct Metadata {
        let authorization: URL
        let token: URL
        let registration: URL?
    }

    private static func discover(base: URL) async throws -> Metadata {
        let url = base.appendingPathComponent(".well-known/oauth-authorization-server")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard ok(response),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = (json["authorization_endpoint"] as? String).flatMap(URL.init(string:)),
              let token = (json["token_endpoint"] as? String).flatMap(URL.init(string:))
        else { throw Failure.discovery(body(data)) }
        return Metadata(
            authorization: auth,
            token: token,
            registration: (json["registration_endpoint"] as? String).flatMap(URL.init(string:))
        )
    }

    /// Registered client IDs are per-server and not secret; keeping the last
    /// one avoids a new registration row on every sign-in. The redirect URI
    /// is part of the key: the server matches it exactly against what was
    /// registered, so a client registered under an older redirect would
    /// fail every sign-in forever.
    private static func clientIDKey(for base: String) -> String {
        "oauth.clientID." + base + "|" + redirectURI
    }

    private static func registerClient(metadata: Metadata) async throws -> String {
        let key = clientIDKey(for: SyncSettings.baseURL)
        if let existing = SharedDefaults.string(forKey: key), !existing.isEmpty { return existing }
        guard let endpoint = metadata.registration else {
            throw Failure.registration("server offers no dynamic registration")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_name": "Oyloo",
            "redirect_uris": [redirectURI],
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "application_type": "native",
            "token_endpoint_auth_method": "none"
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard ok(response),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["client_id"] as? String
        else { throw Failure.registration(body(data)) }
        SharedDefaults.set(id, forKey: key)
        return id
    }

    @MainActor
    private static func present(authURL: URL, anchor: ASPresentationAnchor?) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL, callbackURLScheme: callbackScheme
            ) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(
                        throwing: Failure.authorization(error?.localizedDescription ?? "cancelled")
                    )
                }
            }
            let provider = PresentationProvider(anchor: anchor)
            session.presentationContextProvider = provider
            // Fresh session: a shared cookie jar would sign everyone in as
            // whoever used the browser last, which is exactly wrong on a
            // family device.
            session.prefersEphemeralWebBrowserSession = true
            retainedProvider = provider
            session.start()
        }
    }

    private static func exchange(
        code: String, verifier: String, clientID: String, endpoint: URL
    ) async throws -> TokenStore.Tokens {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard ok(response) else { throw Failure.token(body(data)) }
        return try decodeTokens(data, clientID: clientID)
    }

    /// RFC 7009-style revocation, the server's own shape: JSON with the token
    /// and the client it was issued to. Either token of the pair retires the
    /// whole pair, so the refresh token is the one to send when there is one.
    private static func revoke(token: String, clientID: String, base: URL) async {
        var request = URLRequest(url: base.appendingPathComponent("api/oauth/revoke"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "token": token,
            "client_id": clientID
        ])
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Helpers

    private static func decodeTokens(_ data: Data, clientID: String) throws -> TokenStore.Tokens {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String
        else { throw Failure.token(body(data)) }
        let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue
        return TokenStore.Tokens(
            accessToken: access,
            refreshToken: json["refresh_token"] as? String,
            expiresAt: expiresIn.map { Date().addingTimeInterval($0) },
            clientID: clientID
        )
    }

    private static func ok(_ response: URLResponse) -> Bool {
        (200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private static func body(_ data: Data) -> String {
        String(data: data.prefix(300), encoding: .utf8) ?? "unreadable response"
    }

    private static func form(_ fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private static func randomString(_ bytes: Int) -> String {
        var raw = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &raw)
        return Data(raw).base64URLEncoded
    }

    /// ASWebAuthenticationSession keeps only a weak reference to its context
    /// provider; without holding it the sheet closes itself immediately.
    private static var retainedProvider: PresentationProvider?

    private final class PresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
        private let anchor: ASPresentationAnchor?
        init(anchor: ASPresentationAnchor?) { self.anchor = anchor }
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            anchor ?? ASPresentationAnchor()
        }
    }
}

extension Data {
    /// base64url without padding, as PKCE and OAuth ask for.
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
