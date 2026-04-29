import SwiftUI

@main
struct LifeOSShareApp: App {
    @State private var vaultStore = VaultStore()

    var body: some Scene {
        WindowGroup {
            ContentView(vaultStore: vaultStore)
        }
    }
}
