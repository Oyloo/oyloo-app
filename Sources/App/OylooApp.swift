import SwiftUI
import os

@main
struct OylooApp: App {
    @State private var vaultStore = VaultStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // What the share extension saw the last time it ran, relayed through
        // shared storage because its own log needs a cable to read. Counts,
        // flags and status codes only.
        let lastShare = SharedDefaults.string(forKey: SharedDefaults.lastShareDiagnosticsKey) ?? "none"
        Diagnostics.share.notice("last share from extension: \(lastShare, privacy: .public)")
        let lastUpload = SharedDefaults.string(forKey: SharedDefaults.lastUploadDiagnosticsKey) ?? "none"
        Diagnostics.sync.notice("last upload from extension: \(lastUpload, privacy: .public)")
    }

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
