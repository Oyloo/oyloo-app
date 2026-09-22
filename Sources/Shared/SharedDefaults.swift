import Foundation
import Security
import os

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
    private static let service = "com.oyloo.life.shared"

    /// True when the App Group container is really available.
    public static var usesAppGroup: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroupID) != nil
    }

    private static var groupDefaults: UserDefaults? {
        usesAppGroup ? UserDefaults(suiteName: SharedStore.appGroupID) : nil
    }

    /// Logged once per process, the first time a value is read or written: the
    /// app and the extension must agree on the backing, and when they disagree
    /// the symptom is silent (the extension shows an empty vault list). One
    /// line per process in the syslog says which side chose what.
    private static let backendAnnounced: Bool = {
        let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroupID)
        Diagnostics.storage.notice(
            """
            backend process=\(Diagnostics.process, privacy: .public) \
            usesAppGroup=\(container != nil, privacy: .public) \
            group=\(SharedStore.appGroupID, privacy: .public) \
            container=\(container?.path ?? "nil", privacy: .public) \
            service=\(service, privacy: .public)
            """
        )
        return true
    }()

    private static func announceBackend() {
        _ = backendAnnounced
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
        announceBackend()
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        let data = status == errSecSuccess ? out as? Data : nil
        // errSecItemNotFound is ordinary (nothing stored yet); anything else,
        // above all errSecMissingEntitlement (-34018), means the two processes
        // are not sharing a keychain group at all.
        Diagnostics.storage.notice(
            """
            keychain read process=\(Diagnostics.process, privacy: .public) \
            key=\(key, privacy: .public) status=\(status, privacy: .public) \
            bytes=\(data?.count ?? -1, privacy: .public)
            """
        )
        return data
    }

    private static func setKeychainData(_ value: Data?, forKey key: String) {
        announceBackend()
        let q = query(key)
        let deleted = SecItemDelete(q as CFDictionary)
        guard let value else {
            Diagnostics.storage.notice(
                """
                keychain clear process=\(Diagnostics.process, privacy: .public) \
                key=\(key, privacy: .public) status=\(deleted, privacy: .public)
                """
            )
            return
        }
        var add = q
        add[kSecValueData as String] = value
        // afterFirstUnlock, not whenUnlocked: the share extension may run while
        // the screen is locked, and a value it cannot read is a failed capture.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        Diagnostics.storage.notice(
            """
            keychain write process=\(Diagnostics.process, privacy: .public) \
            key=\(key, privacy: .public) bytes=\(value.count, privacy: .public) \
            status=\(status, privacy: .public)
            """
        )
    }
}
