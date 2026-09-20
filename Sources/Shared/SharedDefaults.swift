import Foundation
import Security

/// Small settings shared between the app and its share extension.
///
/// Two backings, picked at runtime:
///
/// - **App Group** when the group container exists. Plain, fast, what a paid
///   developer account gives you.
/// - **Shared keychain** otherwise. A free provisioning team cannot have App
///   Groups at all (Apple refuses to issue the entitlement), but it can have a
///   keychain access group, and that is enough for a handful of small values.
///
/// The keychain items carry no explicit access group: iOS then files them
/// under the *first* group in `keychain-access-groups`, which is the only one
/// this app declares. That keeps the team prefix out of the source, where it
/// would be both wrong across teams and a nuisance to maintain.
public enum SharedDefaults {
    private static let service = "com.oyloo.lifeos.shared"

    /// True when the App Group container is really available.
    public static var usesAppGroup: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroupID) != nil
    }

    private static var groupDefaults: UserDefaults? {
        usesAppGroup ? UserDefaults(suiteName: SharedStore.appGroupID) : nil
    }

    // MARK: - Values

    public static func string(forKey key: String) -> String? {
        if let defaults = groupDefaults { return defaults.string(forKey: key) }
        guard let data = keychainData(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func set(_ value: String?, forKey key: String) {
        if let defaults = groupDefaults {
            defaults.set(value, forKey: key)
            return
        }
        setKeychainData(value.flatMap { Data($0.utf8) }, forKey: key)
    }

    public static func data(forKey key: String) -> Data? {
        if let defaults = groupDefaults { return defaults.data(forKey: key) }
        return keychainData(forKey: key)
    }

    public static func set(_ value: Data?, forKey key: String) {
        if let defaults = groupDefaults {
            defaults.set(value, forKey: key)
            return
        }
        setKeychainData(value, forKey: key)
    }

    // MARK: - Keychain backing

    private static func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    private static func keychainData(forKey key: String) -> Data? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    private static func setKeychainData(_ value: Data?, forKey key: String) {
        let q = query(key)
        SecItemDelete(q as CFDictionary)
        guard let value else { return }
        var add = q
        add[kSecValueData as String] = value
        // afterFirstUnlock, not whenUnlocked: the share extension may run while
        // the screen is locked, and a value it cannot read is a failed capture.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
