import Foundation

public struct SharedItem: Codable, Identifiable, Hashable {
    public let id: UUID
    /// Stable slug of the chosen vault (matches `Vault.key`). The user
    /// defines vaults in app settings; the share extension stamps each
    /// share with the user's selection.
    public let vaultKey: String
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
    /// The user asked for this capture to become a podcast episode. The
    /// server decides what that means; the app only carries the wish.
    public let publish: Bool

    public init(
        vaultKey: String = SharedStore.defaultVaultKey,
        url: String? = nil,
        title: String? = nil,
        text: String? = nil,
        attachmentPath: String? = nil,
        mimeType: String? = nil,
        publish: Bool = false
    ) {
        self.init(
            id: UUID(),
            vaultKey: vaultKey,
            url: url,
            title: title,
            text: text,
            attachmentPath: attachmentPath,
            mimeType: mimeType,
            sharedAt: Date(),
            publish: publish
        )
    }

    private init(
        id: UUID,
        vaultKey: String,
        url: String?,
        title: String?,
        text: String?,
        attachmentPath: String?,
        mimeType: String?,
        sharedAt: Date,
        publish: Bool
    ) {
        self.id = id
        self.vaultKey = vaultKey
        self.url = url
        self.title = title
        self.text = text
        self.attachmentPath = attachmentPath
        self.mimeType = mimeType
        self.sharedAt = sharedAt
        self.publish = publish
    }

    private enum CodingKeys: String, CodingKey {
        case id, vault, vaultKey, url, title, text, attachmentPath, mimeType, sharedAt, publish
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Migration: pre-refactor format had `"vault":"<enum-case>"`
        // with two hardcoded cases. New format is `"vaultKey":"<user-slug>"`.
        // Decode either; fall back to default so the row stays usable.
        let vaultKey: String
        if let key = try? c.decode(String.self, forKey: .vaultKey) {
            vaultKey = key
        } else if let legacy = try? c.decode(String.self, forKey: .vault) {
            vaultKey = legacy
        } else {
            vaultKey = SharedStore.defaultVaultKey
        }
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            vaultKey: vaultKey,
            url: try c.decodeIfPresent(String.self, forKey: .url),
            title: try c.decodeIfPresent(String.self, forKey: .title),
            text: try c.decodeIfPresent(String.self, forKey: .text),
            attachmentPath: try c.decodeIfPresent(String.self, forKey: .attachmentPath),
            mimeType: try c.decodeIfPresent(String.self, forKey: .mimeType),
            sharedAt: try c.decode(Date.self, forKey: .sharedAt),
            publish: try c.decodeIfPresent(Bool.self, forKey: .publish) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(vaultKey, forKey: .vaultKey)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(attachmentPath, forKey: .attachmentPath)
        try c.encodeIfPresent(mimeType, forKey: .mimeType)
        try c.encode(sharedAt, forKey: .sharedAt)
        if publish { try c.encode(publish, forKey: .publish) }
        // Note: legacy `.vault` key intentionally omitted from output —
        // we read both formats but only write the new one.
    }

    /// Returns a copy with `vaultKey` replaced. Used by the share
    /// extension to stamp the user's picker choice onto an item that
    /// was extracted before the choice was made.
    public func with(vaultKey: String, publish: Bool = false) -> SharedItem {
        SharedItem(
            id: self.id,
            vaultKey: vaultKey,
            url: self.url,
            title: self.title,
            text: self.text,
            attachmentPath: self.attachmentPath,
            mimeType: self.mimeType,
            sharedAt: self.sharedAt,
            publish: publish
        )
    }

    public var isAudio: Bool { (mimeType ?? "").hasPrefix("audio/") }
    public var isImage: Bool { (mimeType ?? "").hasPrefix("image/") }
    public var isFile: Bool { attachmentPath != nil && !isImage }
    public var isText: Bool { text != nil }
    public var isLink: Bool { url != nil && attachmentPath == nil && text == nil }
}
