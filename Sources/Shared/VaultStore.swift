import Foundation
import SwiftUI

/// Observable store for user-defined vaults, persisted in App Group
/// `UserDefaults` so both the container app and the share extension see
/// the same set. `@Observable` makes any SwiftUI view rebind when the
/// vault list changes from the same process; the share extension reads
/// fresh on each invocation, so cross-process updates are picked up at
/// the next share.
@Observable
public final class VaultStore {
    public private(set) var vaults: [Vault] = []

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
        guard let data = SharedDefaults.data(forKey: storageKey) else { return [] }
        let decoder = JSONDecoder()
        return (try? decoder.decode([Vault].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(vaults) {
            SharedDefaults.set(data, forKey: storageKey)
        }
    }
}
