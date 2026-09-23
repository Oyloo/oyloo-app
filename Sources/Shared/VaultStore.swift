import Foundation
import SwiftUI
import os

/// Observable store for user-defined vaults, persisted in App Group
/// `UserDefaults` so both the container app and the share extension see
/// the same set. `@Observable` makes any SwiftUI view rebind when the
/// vault list changes from the same process; the share extension reads
/// fresh on each invocation, so cross-process updates are picked up at
/// the next share.
@Observable
public final class VaultStore {
    public private(set) var vaults: [Vault] = []

    /// Keychain status of the last load, for the share extension's
    /// diagnostics line; `errSecSuccess` when the App Group backing is used.
    public private(set) var lastLoadStatus: OSStatus = errSecSuccess

    private let storageKey = "oyloo.vaults.v1"

    public init() {
        self.vaults = loadVaults()
    }

    public func add(_ vault: Vault) {
        vaults.append(vault)
        save()
    }

    public func update(_ vault: Vault) {
        guard let idx = vaults.firstIndex(where: { $0.id == vault.id }) else { return }
        vaults[idx] = vault
        save()
    }

    public func remove(id: UUID) {
        vaults.removeAll { $0.id == id }
        save()
    }

    public func vault(forKey key: String) -> Vault? {
        vaults.first { $0.key == key }
    }

    /// Re-read from defaults. Useful when returning to foreground in case
    /// the share extension added/changed something.
    public func reload() {
        vaults = loadVaults()
    }

    private func loadVaults() -> [Vault] {
        let data = SharedDefaults.data(forKey: storageKey)
        lastLoadStatus = SharedDefaults.lastReadStatus
        guard let data else {
            Telemetry.event("vaults.load", scope: .storage, ["result": .name("absent")])
            return []
        }
        let decoder = JSONDecoder()
        guard let vaults = try? decoder.decode([Vault].self, from: data) else {
            // Stored bytes that do not decode look exactly like "no vaults" in
            // the UI, so they get their own line.
            Telemetry.event("vaults.load", scope: .storage, severity: .error, [
                "result": .name("undecodable"),
                "bytes": .count(data.count)
            ])
            return []
        }
        // Count only: vault keys are user-chosen names.
        Telemetry.event("vaults.load", scope: .storage, [
            "result": .name("ok"),
            "count": .count(vaults.count)
        ])
        return vaults
    }

    private func save() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(vaults) else {
            Telemetry.event("vaults.save", scope: .storage, severity: .error, [
                "result": .name("encode-failed")
            ])
            return
        }
        Telemetry.event("vaults.save", scope: .storage, [
            "result": .name("ok"),
            "count": .count(vaults.count),
            "bytes": .count(data.count)
        ])
        SharedDefaults.set(data, forKey: storageKey)
    }
}
