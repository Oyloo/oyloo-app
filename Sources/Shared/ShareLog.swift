import Foundation

/// Append-only diagnostic log shared between the extension and the
/// container app via the App Group container. The extension writes one
/// line per significant event (provider list seen, extractor chosen,
/// final SharedItem); the container app's Debug tab reads + displays
/// the file. Trimmed from the head when it grows beyond `maxBytes` so
/// it can't fill the container.
public enum ShareLog {
    public static let logFileName = "share-debug.log"
    public static let maxBytes = 64 * 1024  // 64 KB

    public static var logURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroupID)?
            .appendingPathComponent(logFileName)
    }

    public static func write(_ message: String) {
        guard let url = logURL else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let fm = FileManager.default

        if !fm.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
            return
        }

        // Truncate to the last `maxBytes / 2` if appending would push
        // the file past the cap. Cheap, non-atomic — log integrity is
        // not safety-critical.
        if let attrs = try? fm.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int,
           size + data.count > maxBytes,
           let existing = try? Data(contentsOf: url) {
            let trimmed = existing.suffix(maxBytes / 2)
            try? trimmed.write(to: url, options: .atomic)
        }

        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    public static func read() -> String {
        guard let url = logURL,
              let data = try? Data(contentsOf: url),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    public static func clear() {
        guard let url = logURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
