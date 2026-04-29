import Foundation

/// Destination vault for a captured share. The picker in the share
/// extension assigns this; the container app reads both outboxes and
/// renders a per-row badge. Sync workers (future) ship each outbox to
/// its respective backend (life-os vs also-os).
public enum Vault: String, Codable, CaseIterable, Hashable {
    case life
    case work

    public var displayName: String {
        switch self {
        case .life: return "Life"
        case .work: return "Work"
        }
    }

    public var symbolName: String {
        switch self {
        case .life: return "heart.fill"
        case .work: return "briefcase.fill"
        }
    }
}

public struct SharedItem: Codable, Identifiable, Hashable {
    public let id: UUID
    /// Destination vault. Defaults to `.life` when decoding legacy rows
    /// that pre-date the picker (no field present in JSON).
    public let vault: Vault
    /// Source URL when sharing a link / web page. `nil` for plain-text
    /// quotes and standalone attachments.
    public let url: String?
    /// Display title — page title for URLs, filename for files,
    /// optional human label for text/image.
    public let title: String?
    /// Selected text content for plain-text shares (highlight from a
    /// page, copied snippet). `nil` for non-text shares.
    public let text: String?
    /// Relative path under the App Group container for binary
    /// attachments (`attachments/<uuid>.<ext>`). `nil` if no file.
    public let attachmentPath: String?
    /// MIME type of `attachmentPath` (`image/jpeg`, `application/pdf`,
    /// etc.) — drives the row renderer.
    public let mimeType: String?
    public let sharedAt: Date

    public init(
        vault: Vault = .life,
        url: String? = nil,
        title: String? = nil,
        text: String? = nil,
        attachmentPath: String? = nil,
        mimeType: String? = nil
    ) {
        self.init(
            id: UUID(),
            vault: vault,
            url: url,
            title: title,
            text: text,
            attachmentPath: attachmentPath,
            mimeType: mimeType,
            sharedAt: Date()
        )
    }

    private init(
        id: UUID,
        vault: Vault,
        url: String?,
        title: String?,
        text: String?,
        attachmentPath: String?,
        mimeType: String?,
        sharedAt: Date
    ) {
        self.id = id
        self.vault = vault
        self.url = url
        self.title = title
        self.text = text
        self.attachmentPath = attachmentPath
        self.mimeType = mimeType
        self.sharedAt = sharedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, vault, url, title, text, attachmentPath, mimeType, sharedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let vault = (try? c.decode(Vault.self, forKey: .vault)) ?? .life
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            vault: vault,
            url: try c.decodeIfPresent(String.self, forKey: .url),
            title: try c.decodeIfPresent(String.self, forKey: .title),
            text: try c.decodeIfPresent(String.self, forKey: .text),
            attachmentPath: try c.decodeIfPresent(String.self, forKey: .attachmentPath),
            mimeType: try c.decodeIfPresent(String.self, forKey: .mimeType),
            sharedAt: try c.decode(Date.self, forKey: .sharedAt)
        )
    }

    /// Returns a copy of this item with `vault` replaced. Used by the
    /// share extension to stamp the user's picker choice onto an item
    /// that was extracted before the choice was made. Preserves `id`
    /// and `sharedAt` so the row identity is stable.
    public func with(vault: Vault) -> SharedItem {
        SharedItem(
            id: self.id,
            vault: vault,
            url: self.url,
            title: self.title,
            text: self.text,
            attachmentPath: self.attachmentPath,
            mimeType: self.mimeType,
            sharedAt: self.sharedAt
        )
    }

    public var isImage: Bool { (mimeType ?? "").hasPrefix("image/") }
    public var isFile: Bool { attachmentPath != nil && !isImage }
    public var isText: Bool { text != nil }
    public var isLink: Bool { url != nil && attachmentPath == nil && text == nil }
}
