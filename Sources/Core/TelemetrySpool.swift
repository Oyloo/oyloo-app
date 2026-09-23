import Foundation

/// Telemetry batches that could not be sent, kept on disk until they can.
///
/// The share extension lives for seconds, so a batch that fails there is gone
/// unless it is written down. Caps rather than a policy: telemetry is never
/// worth a full disk or a slow launch, so the spool keeps the newest few files
/// and forgets anything older than its age limit. A capture is never gated on
/// any of this.
public struct TelemetrySpool: Sendable {
    public let directory: URL
    public let maxFiles: Int
    public let maxAge: TimeInterval

    public init(directory: URL, maxFiles: Int = 64, maxAge: TimeInterval = 7 * 24 * 60 * 60) {
        self.directory = directory
        self.maxFiles = maxFiles
        self.maxAge = maxAge
    }

    /// The spool for one signal in this process's own container.
    public static func forSignal(_ signal: String) -> TelemetrySpool? {
        guard let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return TelemetrySpool(
            directory: support.appendingPathComponent("telemetry-spool/\(signal)", isDirectory: true)
        )
    }

    public func write(_ body: Data?, at date: Date = Date()) {
        guard let body, !body.isEmpty else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // The time leads the name and is zero-padded, so name order is age
        // order and nothing has to read file attributes to sort.
        let stamp = String(format: "%015.3f", date.timeIntervalSince1970)
        let url = directory.appendingPathComponent("\(stamp)-\(UUID().uuidString).otlp")
        try? body.write(to: url, options: .atomic)
        trim(now: date)
    }

    /// Reads and removes everything still within the age limit, oldest first.
    /// Removal happens up front on purpose: a body that fails again is written
    /// back, which is simpler than tracking half-consumed files.
    public func take(now: Date = Date()) -> [Data] {
        trim(now: now)
        return files().compactMap { url in
            defer { try? FileManager.default.removeItem(at: url) }
            return try? Data(contentsOf: url)
        }
    }

    private func files() -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        return entries.filter { $0.pathExtension == "otlp" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func trim(now: Date) {
        let cutoff = now.timeIntervalSince1970 - maxAge
        var kept: [URL] = []
        for url in files() {
            let stamp = Double(url.lastPathComponent.prefix { $0 != "-" }) ?? 0
            if stamp < cutoff {
                try? FileManager.default.removeItem(at: url)
            } else {
                kept.append(url)
            }
        }
        for url in kept.prefix(max(0, kept.count - maxFiles)) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
