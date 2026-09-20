import SwiftUI

@main
struct OylooApp: App {
    @State private var vaultStore = VaultStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(vaultStore: vaultStore)
                .onChange(of: scenePhase) { _, phase in
                    // Opening the app is the one moment we are certain to have
                    // both network and foreground time: ship whatever the
                    // share extension collected since last time.
                    guard phase == .active, SyncSettings.isConfigured else { return }
                    Task { _ = await Uploader.syncAll() }
                }
        }
    }
}
