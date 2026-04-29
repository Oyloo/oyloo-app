import SwiftUI

@main
struct OylooApp: App {
    @State private var vaultStore = VaultStore()

    var body: some Scene {
        WindowGroup {
            ContentView(vaultStore: vaultStore)
        }
    }
}
