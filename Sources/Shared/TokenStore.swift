import Foundation
import Security

/// Tokens live in the keychain, not in defaults: they are credentials, and the
/// device may be shared with the rest of the family. One entry per server, so
/// signing into a different server does not silently reuse the old session.
public enum TokenStore {
    public struct Tokens: Codable, Sendable {
        public var accessToken: String
        public var refreshToken: String?
        public var expiresAt: Date?
        public var clientID: String

        public var isFresh: Bool {
            guard let expiresAt else { return true }
            // A minute of slack: a token that dies mid-upload is worse than
            // one refreshed slightly early.
            return expiresAt.timeIntervalSinceNow > 60
        }
    }

    private static let service = "com.oyloo.life.oauth"

    private static func query(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    public static func save(_ tokens: Tokens, for account: String) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        var q = query(for: account)
        SecItemDelete(q as CFDictionary)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    public static func load(for account: String) -> Tokens? {
        var q = query(for: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Tokens.self, from: data)
    }

    public static func clear(for account: String) {
        SecItemDelete(query(for: account) as CFDictionary)
    }
}
