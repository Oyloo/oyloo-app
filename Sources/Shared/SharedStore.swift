import Foundation

/// Append-only JSONL outboxes shared between the container app and the
/// share extension via App Group container. One outbox file per vault
/// (`outbox-life.jsonl`, `outbox-work.jsonl`); routing is by
/// `item.vault`. Future sync workers tail each file and ship to the
/// matching backend (life-os vs also-os).
public enum SharedStore {
    public static let appGroupID = "group.com.oyloo.lifeos"

    /// Legacy single outbox written before the picker landed. Reads
    /// migrate its contents into the per-vault files, then it is
    /// deleted. Decoded rows default to `.life` per `SharedItem`'s
    /// custom Codable init.
    public static let legacyOutboxFileName = "outbox.jsonl"

    public static func outboxFileName(for vault: Vault) -> String {
        "outbox-\(vault.rawValue).jsonl"
    }

    public static func outboxURL(for vault: Vault) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(outboxFileName(for: vault))
    }

    private static var legacyOutboxURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(legacyOutboxFileName)
    }

    /// Hard cap on attachment size to stay under iOS share-extension
    /// memory limits (extensions die at ~120 MB on modern devices).
    public static let maxAttachmentBytes = 30 * 1024 * 1024  // 30 MB

    /// Lazy directory for binary attachments under the App Group container.
    public static var attachmentsDirectory: URL? {
        guard let group = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return nil }
        let dir = group.appendingPathComponent("attachments", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Save raw attachment bytes under `attachments/<uuid>.<ext>`.
    /// Returns the path RELATIVE to the App Group container so the
    /// container app can resolve it via `resolveAttachment(_:)`.
    public static func saveAttachment(_ data: Data, fileExtension: String) -> String? {
        guard data.count <= maxAttachmentBytes else { return nil }
        guard let dir = attachmentsDirectory else { return nil }
        let ext = fileExtension.isEmpty ? "bin" : fileExtension
        let filename = "\(UUID().uuidString).\(ext)"
        let url = dir.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return "attachments/\(filename)"
        } catch {
            return nil
        }
    }

    /// Resolve a relative attachment path back to an absolute URL on
    /// disk inside the App Group container.
    public static func resolveAttachment(_ relativePath: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(relativePath)
    }

    /// Delete the attachment file (if any) for an item. Called from
    /// swipe-to-delete; safe to call on items without attachments.
    public static func deleteAttachment(of item: SharedItem) {
        guard let path = item.attachmentPath,
              let url = resolveAttachment(path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Append an item to the outbox file matching its vault.
    public static func append(_ item: SharedItem) {
        guard let url = outboxURL(for: item.vault) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(item) else { return }
        data.append(0x0A)

        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Swallow — outbox is best-effort; the user can re-share.
        }
    }

    /// Read items from a single vault's outbox. Returns empty when the
    /// file does not exist yet.
    public static func readAll(vault: Vault) -> [SharedItem] {
        guard let url = outboxURL(for: vault),
              let data = try? Data(contentsOf: url) else { return [] }
        return decodeJSONL(data)
    }

    /// Read all items from every vault, plus any legacy rows from the
    /// pre-picker outbox (decoded as `.life`). Migrates legacy rows
    /// into the per-vault files on first read so the legacy file can
    /// be removed.
    public static func readAll() -> [SharedItem] {
        migrateLegacyOutboxIfPresent()
        return Vault.allCases.flatMap { readAll(vault: $0) }
    }

    /// Atomic full-rewrite of one vault's outbox. Used by the container
    /// app for swipe-to-delete; the extension only ever appends.
    public static func replaceAll(_ items: [SharedItem], vault: Vault) {
        guard let url = outboxURL(for: vault) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = Data()
        for item in items where item.vault == vault {
            if let line = try? encoder.encode(item) {
                data.append(line)
                data.append(0x0A)
            }
        }
        try? data.write(to: url, options: .atomic)
    }

    /// Convenience for callers that already have a mixed-vault list and
    /// want to persist deletions back. Splits by vault and rewrites
    /// each outbox file atomically.
    public static func replaceAll(_ items: [SharedItem]) {
        for vault in Vault.allCases {
            replaceAll(items, vault: vault)
        }
    }

    private static func decodeJSONL(_ data: Data) -> [SharedItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).compactMap { line in
            try? decoder.decode(SharedItem.self, from: Data(line))
        }
    }

    /// One-shot migration of the pre-picker `outbox.jsonl` into the
    /// per-vault files. All legacy rows decode as `.life`. Idempotent —
    /// after the first successful migration the legacy file is removed.
    private static func migrateLegacyOutboxIfPresent() {
        guard let url = legacyOutboxURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return }
        let items = decodeJSONL(data)
        for item in items { append(item) }
        try? FileManager.default.removeItem(at: url)
    }
}
