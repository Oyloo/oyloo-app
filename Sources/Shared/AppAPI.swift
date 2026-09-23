import Foundation

/// The family app API: one place that knows paths, the bearer token and the
/// cache. Every successful GET also lands in the cache, so the next launch
/// shows it before the network answers.
public enum AppAPI {
    public enum Failure: LocalizedError {
        case notConfigured
        case notSignedIn
        case http(Int)

        public var errorDescription: String? {
            switch self {
            case .notConfigured: String(localized: "Set the server address in Settings.")
            case .notSignedIn: String(localized: "Sign in to see this.")
            case .http(401): String(localized: "The server refused the sign-in. Sign in again.")
            case .http(403): String(localized: "This account has no access here.")
            case .http(let code): String(localized: "The server answered \(code).")
            }
        }
    }

    public static var cache: ResponseCache { ResponseCache.forServer(SyncSettings.baseURL) }

    public static func me() async throws -> CachedBody { try await get("me") }
    public static func money() async throws -> CachedBody { try await get("money") }
    public static func tasks(view: String) async throws -> CachedBody {
        try await get("tasks", query: [URLQueryItem(name: "view", value: view)])
    }

    public static func completeTask(id: String) async throws {
        var request = try await request(path: "tasks/\(id)")
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["status": "done"])
        let (_, response) = try await URLSession.shared.data(for: request)
        try check(response)
    }

    /// Cache key for a call; the same string `CachedResource` reads back.
    public static func key(_ path: String, query: [URLQueryItem] = []) -> String {
        query.isEmpty ? path : path + "?" + query.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
    }

    private static func get(_ path: String, query: [URLQueryItem] = []) async throws -> CachedBody {
        var request = try await request(path: path, query: query)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response)
        let now = Date()
        try? cache.store(data, for: key(path, query: query), at: now)
        return CachedBody(data: data, fetchedAt: now)
    }

    private static func request(path: String, query: [URLQueryItem] = []) async throws -> URLRequest {
        guard SyncSettings.isConfigured, let base = URL(string: SyncSettings.baseURL) else {
            throw Failure.notConfigured
        }
        var components = URLComponents(
            url: base.appendingPathComponent("api/app/v1/" + path), resolvingAgainstBaseURL: false
        )
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw Failure.notConfigured }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        guard let token = try? await OAuthClient.validAccessToken() else { throw Failure.notSignedIn }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func check(_ response: URLResponse) throws {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw Failure.http(code) }
    }
}
