import Foundation
import Observation

/// A value from the API that screens can show at once from the cache and
/// refresh from the network. A failed refresh keeps the cached value and
/// records why, so the screen can say both what it has and what went wrong.
@MainActor
@Observable
public final class CachedResource<Value: Decodable & Sendable> {
    public private(set) var value: Value?
    public private(set) var fetchedAt: Date?
    public private(set) var error: String?
    public private(set) var isLoading = false

    private let key: String
    private let fetch: @Sendable () async throws -> CachedBody

    public init(key: String, fetch: @escaping @Sendable () async throws -> CachedBody) {
        self.key = key
        self.fetch = fetch
        if let cached = AppAPI.cache.load(key), let decoded = Self.decode(cached.data) {
            value = decoded
            fetchedAt = cached.fetchedAt
        }
    }

    public func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let body = try await fetch()
            guard let decoded = Self.decode(body.data) else {
                error = String(localized: "The server sent something this version cannot read.")
                return
            }
            value = decoded
            fetchedAt = body.fetchedAt
            error = nil
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static func decode(_ data: Data) -> Value? {
        try? AppJSON.decoder.decode(Value.self, from: data)
    }
}
