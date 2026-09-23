import Foundation
import Observation
import os

/// A capture as the server knows it.
///
/// Without an App Group the share extension uploads on its own and the app
/// never sees those files, so the server's list is the only place the whole
/// history exists. Only the fields the list needs are decoded; the endpoint
/// sends more.
public struct ServerCapture: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let vault: String
    public let title: String?
    public let mimeType: String?
    public let byteSize: Int?
    public let transcriptState: String?
    public let podcast: Bool?
    public let createdAt: Date

    public var isTranscribed: Bool { transcriptState == "done" }
    public var isAudio: Bool { mimeType?.hasPrefix("audio/") ?? false }
}

/// Reads the captures the server holds for the signed-in account.
public enum CapturesAPI {
    public enum Failure: LocalizedError {
        case notConfigured
        case notSignedIn
        case http(Int)
        case malformed

        public var errorDescription: String? {
            switch self {
            case .notConfigured: "Set the server address first."
            case .notSignedIn: "Sign in to see captures from the server."
            case .http(401): "The server refused the sign-in. Sign in again."
            case .http(let code): "The server answered \(code)."
            case .malformed: "The server sent something unreadable."
            }
        }
    }

    private struct Envelope: Decodable {
        let items: [ServerCapture]
    }

    /// The listing is capped server-side at 100 rows and is not filtered by
    /// vault there, so the caller filters by `vault` itself.
    public static func fetch(limit: Int = 100) async throws -> [ServerCapture] {
        guard SyncSettings.isConfigured, let base = URL(string: SyncSettings.baseURL) else {
            throw Failure.notConfigured
        }
        var components = URLComponents(
            url: base.appendingPathComponent("api/uploads"), resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        guard let url = components?.url else { throw Failure.notConfigured }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        // Same order as the uploader: the browser session first, a typed
        // token only for servers that speak no OAuth.
        if let bearer = try? await OAuthClient.validAccessToken() {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        } else if !SyncSettings.token.isEmpty {
            request.setValue("Bearer \(SyncSettings.token)", forHTTPHeaderField: "Authorization")
        } else {
            throw Failure.notSignedIn
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            Telemetry.event("captures.fetch", scope: .sync, severity: .error, [
                "result": .name("http"),
                "status": .status(Int32(code))
            ])
            throw Failure.http(code)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else {
            Telemetry.event("captures.fetch", scope: .sync, severity: .error, [
                "result": .name("malformed")
            ])
            throw Failure.malformed
        }
        Telemetry.event("captures.fetch", scope: .sync, [
            "result": .name("ok"),
            "count": .count(envelope.items.count)
        ])
        return envelope.items
    }
}

/// Server-side captures for the list, with the state the UI needs to say why
/// it is empty: never loaded, loading, loaded, or failed with a reason.
@Observable
@MainActor
public final class CaptureFeed {
    public enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public private(set) var captures: [ServerCapture] = []
    public private(set) var state: State = .idle

    public init() {}

    public func captures(forVaultKey key: String) -> [ServerCapture] {
        captures.filter { $0.vault == key }
    }

    /// Refuses to stack requests: pull-to-refresh and the scene becoming
    /// active often land together.
    public func refresh() async {
        guard state != .loading else { return }
        guard SyncSettings.isConfigured else {
            captures = []
            state = .idle
            return
        }
        state = .loading
        do {
            captures = try await CapturesAPI.fetch()
            state = .loaded
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            state = .failed(reason)
        }
    }
}
