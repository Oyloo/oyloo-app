import Foundation

/// Where shipped captures are sent. The base URL is supplied by the user at
/// runtime and stored in the App Group, so nothing about any particular
/// deployment lives in this repo.
///
/// The receiving side is expected to accept `PUT <base>upload?name=<filename>`
/// with the raw file as the request body and answer 2xx on success. A secret
/// path segment inside the base URL is the simplest way to keep a private
/// endpoint private; anything stronger belongs behind a real login.
public enum SyncSettings {
    private static let baseKey = "sync.baseURL"
    private static let tokenKey = "sync.token"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: SharedStore.appGroupID)
    }

    /// User-entered base URL, always kept with a trailing slash.
    public static var baseURL: String {
        get { defaults?.string(forKey: baseKey) ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalised = trimmed.isEmpty || trimmed.hasSuffix("/") ? trimmed : trimmed + "/"
            defaults?.set(normalised, forKey: baseKey)
        }
    }

    /// Optional bearer token, for endpoints behind a real login rather than a
    /// secret path segment.
    public static var token: String {
        get { defaults?.string(forKey: tokenKey) ?? "" }
        set { defaults?.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: tokenKey) }
    }

    public static var isConfigured: Bool {
        guard let url = URL(string: baseURL), url.scheme != nil, url.host != nil else { return false }
        return true
    }

    /// Upload target for one file name.
    public static func uploadURL(filename: String) -> URL? {
        guard isConfigured,
              var components = URLComponents(string: baseURL + "upload") else { return nil }
        components.queryItems = [URLQueryItem(name: "name", value: filename)]
        return components.url
    }
}
