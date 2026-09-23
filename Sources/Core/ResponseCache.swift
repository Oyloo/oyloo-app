import Foundation

public struct CachedBody: Sendable, Equatable {
    public let data: Data
    public let fetchedAt: Date
}

/// Last successful response of each call, kept on disk so screens have
/// something to show without a network. One folder per server; the time
/// a body arrived is the file's modification date, set explicitly.
public struct ResponseCache: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Caches go under the system caches folder by default: the OS may purge
    /// them under storage pressure, which is fine — the next refresh refills.
    public static func forServer(
        _ baseURL: String,
        root: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    ) -> ResponseCache {
        ResponseCache(directory: root
            .appendingPathComponent("app-api", isDirectory: true)
            .appendingPathComponent(safeName(baseURL), isDirectory: true))
    }

    public func store(_ data: Data, for key: String, at date: Date = Date()) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(key)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    public func load(_ key: String) -> CachedBody? {
        let url = fileURL(key)
        guard let data = try? Data(contentsOf: url),
              let date = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        else { return nil }
        return CachedBody(data: data, fetchedAt: date)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func fileURL(_ key: String) -> URL {
        directory.appendingPathComponent(Self.safeName(key) + ".json")
    }

    /// Letters and digits kept, everything else becomes "_" plus a stable
    /// checksum, so "tasks?view=a/b" and "tasks?view=a_b" never collide.
    static func safeName(_ raw: String) -> String {
        let kept = String(raw.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? Character($0) : "_"
        })
        var hash: UInt64 = 1469598103934665603
        for byte in raw.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        return kept.prefix(80) + "-" + String(hash, radix: 16)
    }
}
