import Foundation

/// Where shipped captures are sent. The base URL is supplied by the user at
/// runtime and stored in the App Group, so nothing about any particular
/// deployment lives in this repo.
///
/// The receiving side is expected to accept
/// `PUT <base>api/uploads?name=<filename>&vault=<vault>[&podcast=1]` with the raw file as
/// the request body and answer 2xx on success. Authentication is a bearer
/// token: from browser sign-in when the server speaks OAuth (see
/// `OAuthClient`), or a token typed into settings for a plainer endpoint.
public enum SyncSettings {
    private static let baseKey = "sync.baseURL"
    private static let tokenKey = "sync.token"

    /// User-entered base URL, always kept with a trailing slash.
    public static var baseURL: String {
        get { SharedDefaults.string(forKey: baseKey) ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalised = trimmed.isEmpty || trimmed.hasSuffix("/") ? trimmed : trimmed + "/"
            SharedDefaults.set(normalised, forKey: baseKey)
        }
    }

    /// Optional bearer token, for endpoints behind a real login rather than a
    /// secret path segment.
    public static var token: String {
        get { SharedDefaults.string(forKey: tokenKey) ?? "" }
        set { SharedDefaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: tokenKey) }
    }

    public static var isConfigured: Bool {
        guard let url = URL(string: baseURL), url.scheme != nil, url.host != nil else { return false }
        return true
    }

    /// Upload target for one file.
    public static func uploadURL(filename: String, vault: String, publish: Bool = false) -> URL? {
        guard isConfigured,
              var components = URLComponents(string: baseURL + "api/uploads") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "name", value: filename),
            URLQueryItem(name: "vault", value: vault)
        ]
        if publish { components.queryItems?.append(URLQueryItem(name: "podcast", value: "1")) }
        return components.url
    }
}
