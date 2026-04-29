import Foundation
import SwiftUI
import UIKit

/// User-defined capture vault. The user adds, edits, and removes vaults
/// in the app's settings; the share extension presents the current set
/// as picker buttons. Each share is stamped with the chosen vault's
/// `key`, which determines the outbox file under the App Group container
/// and (later) the sync endpoint.
public struct Vault: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    /// Stable slug used for outbox file naming and sync routing.
    /// Lowercase, no spaces (e.g. "personal", "work", "research").
    public var key: String
    /// User-facing label.
    public var displayName: String
    /// SF Symbol name (e.g. "heart.fill", "briefcase.fill", "leaf.fill").
    public var symbolName: String
    /// Tint as 6-char hex `RRGGBB` (no leading `#`).
    public var tintHex: String

    public init(
        id: UUID = UUID(),
        key: String,
        displayName: String,
        symbolName: String = "folder.fill",
        tintHex: String = "007AFF"
    ) {
        self.id = id
        self.key = key
        self.displayName = displayName
        self.symbolName = symbolName
        self.tintHex = tintHex
    }

    public var tintColor: Color {
        Color(hex: tintHex) ?? .accentColor
    }
}

extension Color {
    /// Parse 6-char (`RRGGBB`) or 8-char (`RRGGBBAA`) hex with optional
    /// leading `#`. Returns `nil` on bad input.
    public init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard let value = UInt32(body, radix: 16) else { return nil }
        let r, g, b, a: UInt32
        switch body.count {
        case 6:
            r = (value >> 16) & 0xFF
            g = (value >> 8)  & 0xFF
            b =  value        & 0xFF
            a = 0xFF
        case 8:
            r = (value >> 24) & 0xFF
            g = (value >> 16) & 0xFF
            b = (value >> 8)  & 0xFF
            a =  value        & 0xFF
        default:
            return nil
        }
        self = Color(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Encode to 6-char `RRGGBB` hex. Drops alpha. Returns `nil` if the
    /// underlying UIColor can't yield RGBA components (e.g. some
    /// catalog colors).
    public func toHex() -> String? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        let ri = Int(round(max(0, min(1, r)) * 255))
        let gi = Int(round(max(0, min(1, g)) * 255))
        let bi = Int(round(max(0, min(1, b)) * 255))
        return String(format: "%02X%02X%02X", ri, gi, bi)
    }
}
