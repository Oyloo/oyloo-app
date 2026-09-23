import Foundation
import OpenTelemetryProtocolExporterHttp
import os

/// How a telemetry batch leaves the phone.
///
/// The OTLP exporters build a `URLRequest` and hand it here. Three things
/// this does that the SDK's own client does not:
///
/// - **Binds the address late.** The exporters are built once, but the server
///   comes from settings and may be entered, changed or cleared afterwards.
///   Every request is re-pointed at the current `SyncSettings` before it is
///   sent, and a request with nowhere to go fails instead of travelling to
///   whatever the exporter was born with.
/// - **Sends synchronously.** The caller is the SDK's batch worker thread,
///   which expects the send to have happened when `export` returns; in the
///   share extension the process may be gone a moment later.
/// - **Spools on failure.** A phone outside the home network, a server that
///   is down, an expired token: the body goes to disk and is replayed before
///   the next send, oldest first. That is the whole offline story — the SDK's
///   in-memory queue dies with the extension.
public final class TelemetryTransport: HTTPClient, @unchecked Sendable {
    private let session: URLSession
    private let spool: TelemetrySpool

    public init(signal: String) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        // Telemetry must never keep a capture waiting: if the network is
        // busy uploading a recording, the batch is spooled rather than
        // queued behind it.
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
        spool = TelemetrySpool(signal: signal)
    }

    // MARK: - HTTPClient

    public func send(request: URLRequest, completion: @escaping (Result<HTTPURLResponse, Error>) -> Void) {
        let result = sendSynchronously(request)
        completion(result)
    }

    public func send(request: URLRequest) async throws -> HTTPURLResponse {
        try sendSynchronously(request).get()
    }

    // MARK: - One send

    private enum TransportError: Error {
        case noServer
        case status(Int)
        case noResponse
    }

    private func sendSynchronously(_ request: URLRequest) -> Result<HTTPURLResponse, Error> {
        guard let endpoint = Telemetry.endpoint(for: spool.signal) else {
            // Nothing to re-point at: hold the body until a server exists.
            spool.write(request.httpBody)
            Telemetry.recordExportOutcome(succeeded: false)
            return .failure(TransportError.noServer)
        }

        // A spooled batch goes first: order matters more than freshness when
        // reading a share that failed an hour ago.
        drainSpool(template: request, endpoint: endpoint)

        var outgoing = request
        outgoing.url = endpoint
        let result = perform(outgoing)
        if case .failure = result {
            spool.write(request.httpBody)
        }
        Telemetry.recordExportOutcome(succeeded: {
            if case .success = result { return true }
            return false
        }())
        return result
    }

    private func drainSpool(template: URLRequest, endpoint: URL) {
        for body in spool.take() {
            var replay = template
            replay.url = endpoint
            replay.httpBody = body
            if case .failure = perform(replay) {
                // Still no luck: put it back and stop, so a long backlog does
                // not hold the worker thread on every export.
                spool.write(body)
                return
            }
        }
    }

    private func perform(_ request: URLRequest) -> Result<HTTPURLResponse, Error> {
        let semaphore = DispatchSemaphore(value: 0)
        var outcome: Result<HTTPURLResponse, Error> = .failure(TransportError.noResponse)
        let task = session.dataTask(with: request) { _, response, error in
            if let error {
                outcome = .failure(error)
            } else if let http = response as? HTTPURLResponse {
                outcome = (200 ..< 300).contains(http.statusCode)
                    ? .success(http)
                    : .failure(TransportError.status(http.statusCode))
            }
            semaphore.signal()
        }
        task.resume()
        if semaphore.wait(timeout: .now() + 20) == .timedOut {
            task.cancel()
            return .failure(TransportError.noResponse)
        }
        return outcome
    }
}

/// Failed batches on disk, in the process's own container.
///
/// Caps rather than a policy: telemetry is never worth a full disk or a slow
/// launch, so the spool keeps the newest few files and forgets anything older
/// than a week. A capture is never gated on any of this.
struct TelemetrySpool {
    let signal: String

    static let maxFiles = 64
    static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    private var directory: URL? {
        guard let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = support.appendingPathComponent("telemetry-spool/\(signal)", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func write(_ body: Data?) {
        guard let body, !body.isEmpty, let directory else { return }
        let name = "\(Date().timeIntervalSince1970)-\(UUID().uuidString).otlp"
        try? body.write(to: directory.appendingPathComponent(name), options: .atomic)
        trim()
    }

    /// Reads and removes everything currently spooled, oldest first. Removal
    /// happens up front on purpose: a body that fails again is written back,
    /// and that is cheaper than reasoning about half-consumed files.
    func take() -> [Data] {
        guard let directory,
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: directory, includingPropertiesForKeys: nil
              ) else { return [] }
        let files = entries.filter { $0.pathExtension == "otlp" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return files.compactMap { url in
            defer { try? FileManager.default.removeItem(at: url) }
            return try? Data(contentsOf: url)
        }
    }

    private func trim() {
        guard let directory,
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: directory, includingPropertiesForKeys: [.creationDateKey]
              ) else { return }
        let files = entries.filter { $0.pathExtension == "otlp" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        for url in files {
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            if let created, created < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let remaining = files.filter { FileManager.default.fileExists(atPath: $0.path) }
        if remaining.count > Self.maxFiles {
            for url in remaining.prefix(remaining.count - Self.maxFiles) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
