import Foundation

/// Append-only JSONL outboxes shared between the container app and the
/// share extension via App Group container. One outbox file per vault
/// key (`outbox-<key>.jsonl`); routing is by `item.vaultKey`. Future
/// sync workers tail each file and ship to the matching backend.
public enum SharedStore {
    public static let appGroupID = "group.com.oyloo.lifeos"

    /// Где живут outbox и вложения.
    ///
    /// App Group, когда он выдан (платная команда): тогда расширение и
    /// приложение видят одни и те же файлы. Иначе собственный контейнер
    /// процесса: на бесплатной команде App Group не выдаётся вовсе, и
    /// расширение в этом случае отправляет захват само, не передавая его
    /// приложению (см. ShareViewController).
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    /// Pre-refactor single outbox written before the picker landed.
    /// Migrated into per-vault files on first read; legacy file is
    /// removed afterwards.
    public static let legacyOutboxFileName = "outbox.jsonl"

    /// Default vault key used when decoding legacy items that have no
    /// `vaultKey` and no `vault` field (defensive fallback).
    public static let defaultVaultKey = "default"

    public static func outboxFileName(forKey key: String) -> String {
        "outbox-\(key).jsonl"
    }

    public static func outboxURL(forKey key: String) -> URL? {
        containerURL?.appendingPathComponent(outboxFileName(forKey: key))
    }

    private static var legacyOutboxURL: URL? {
        containerURL?.appendingPathComponent(legacyOutboxFileName)
    }

    /// Hard cap on attachment size to stay under iOS share-extension
    /// memory limits (extensions die at ~120 MB on modern devices).
    public static let maxAttachmentBytes = 30 * 1024 * 1024  // 30 MB

    /// Lazy directory for binary attachments under the App Group container.
    public static var attachmentsDirectory: URL? {
        guard let group = containerURL else { return nil }
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

    /// Copy an already-on-disk attachment into the App Group container
    /// WITHOUT loading it into memory. Share extensions are killed around
    /// 120 MB, so reading a long recording with `Data(contentsOf:)` fails
    /// where a copy succeeds; there is no size cap on this path.
    /// Returns the path RELATIVE to the container, like `saveAttachment`.
    public static func copyAttachment(from source: URL, fileExtension: String) -> String? {
        guard let dir = attachmentsDirectory else { return nil }
        let ext = fileExtension.isEmpty ? "bin" : fileExtension
        let filename = "\(UUID().uuidString).\(ext)"
        let destination = dir.appendingPathComponent(filename)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return "attachments/\(filename)"
        } catch {
            return nil
        }
    }

    // MARK: - Shipped items

    private static let shippedFileName = "shipped.txt"

    private static var shippedURL: URL? {
        containerURL?.appendingPathComponent(shippedFileName)
    }

    private static var shippedCache: Set<String>?

    /// IDs already accepted by the sync target. Kept in a plain file rather
    /// than rewriting the outbox, so shipping never risks the capture log.
    public static func isShipped(_ id: UUID) -> Bool {
        if shippedCache == nil {
            let raw = shippedURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
            shippedCache = Set(raw.split(separator: "\n").map(String.init))
        }
        return shippedCache?.contains(id.uuidString) ?? false
    }

    public static func markShipped(_ id: UUID) {
        guard let url = shippedURL else { return }
        shippedCache?.insert(id.uuidString)
        guard let data = (id.uuidString + "\n").data(using: .utf8) else { return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    /// Resolve a relative attachment path back to an absolute URL on
    /// disk inside the App Group container.
    public static func resolveAttachment(_ relativePath: String) -> URL? {
        containerURL?.appendingPathComponent(relativePath)
    }

    /// Delete the attachment file (if any) for an item. Called from
    /// swipe-to-delete; safe to call on items without attachments.
    public static func deleteAttachment(of item: SharedItem) {
        guard let path = item.attachmentPath,
              let url = resolveAttachment(path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Append an item to the outbox file matching its vault key.
    public static func append(_ item: SharedItem) {
        guard let url = outboxURL(forKey: item.vaultKey) else { return }
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
    public static func readAll(vaultKey: String) -> [SharedItem] {
        guard let url = outboxURL(forKey: vaultKey),
              let data = try? Data(contentsOf: url) else { return [] }
        return decodeJSONL(data)
    }

    /// Read items from every outbox file currently present in the App
    /// Group container, plus migrate any legacy single-file outbox.
    /// Discovers outboxes by name pattern (`outbox-*.jsonl`) so newly
    /// added vaults are picked up automatically without changes here.
    public static func readAll() -> [SharedItem] {
        migrateLegacyOutboxIfPresent()
        guard let container = containerURL,
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: container,
                  includingPropertiesForKeys: nil
              ) else { return [] }

        let outboxes = entries.filter { url in
            let name = url.lastPathComponent
            return name.hasPrefix("outbox-") && name.hasSuffix(".jsonl")
        }
        return outboxes.flatMap { url -> [SharedItem] in
            guard let data = try? Data(contentsOf: url) else { return [] }
            return decodeJSONL(data)
        }
    }

    /// Atomic full-rewrite of one vault's outbox. Empty list removes the
    /// outbox file (no zero-byte residue in the container).
    public static func replaceAll(_ items: [SharedItem], forVaultKey vaultKey: String) {
        guard let url = outboxURL(forKey: vaultKey) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = Data()
        for item in items where item.vaultKey == vaultKey {
            if let line = try? encoder.encode(item) {
                data.append(line)
                data.append(0x0A)
            }
        }
        if data.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Convenience for callers that hold a mixed-vault list (e.g. the
    /// container app's delete handler). Splits by vault key, rewrites
    /// the outboxes that contain remaining items, and removes outbox
    /// files for vault keys that now have zero items.
    public static func replaceAll(_ items: [SharedItem]) {
        let grouped = Dictionary(grouping: items, by: { $0.vaultKey })
        for (key, items) in grouped {
            replaceAll(items, forVaultKey: key)
        }
        let activeKeys = Set(grouped.keys)
        guard let container = containerURL,
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: container,
                  includingPropertiesForKeys: nil
              ) else { return }
        for url in entries where url.lastPathComponent.hasPrefix("outbox-")
                                && url.lastPathComponent.hasSuffix(".jsonl") {
            let key = url.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "outbox-", with: "")
            if !activeKeys.contains(key) {
                try? FileManager.default.removeItem(at: url)
            }
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
    /// per-vault files. Legacy rows decode with the default vault key.
    /// Idempotent — after the first successful migration the legacy
    /// file is removed.
    private static func migrateLegacyOutboxIfPresent() {
        guard let url = legacyOutboxURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return }
        for item in decodeJSONL(data) { append(item) }
        try? FileManager.default.removeItem(at: url)
    }
}
