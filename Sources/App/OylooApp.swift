import SwiftUI
import os

@main
struct OylooApp: App {
    @State private var vaultStore = VaultStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Telemetry.start()
        // The extension exports its own records now. What is left here is the
        // fallback: a line it wrote because its export did not get through.
        // Re-emitting it from this process is the second chance to reach the
        // collector, and clearing it stops the same line arriving forever.
        drainRelay(SharedDefaults.lastShareDiagnosticsKey, as: "share.relay")
        drainRelay(SharedDefaults.lastUploadDiagnosticsKey, as: "upload.relay")
    }

    /// The relayed line is written by our own extension and holds only counts,
    /// flags and status codes (see `Uploader.Report.diagnostics`), so it may
    /// travel as an attribute.
    private func drainRelay(_ key: String, as event: String) {
        guard let line = SharedDefaults.string(forKey: key), !line.isEmpty else { return }
        Telemetry.event(event, scope: .share, ["relay.line": .name(line)])
        SharedDefaults.set(nil as String?, forKey: key)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(vaultStore: vaultStore)
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        // Opening the app is the one moment we are certain to
                        // have both network and foreground time: ship whatever
                        // the share extension collected since last time, and
                        // drain whatever telemetry has been waiting on disk.
                        Task {
                            await Telemetry.refreshAuthorization()
                            if SyncSettings.isConfigured { _ = await Uploader.syncAll() }
                            await Telemetry.flushWithFreshToken()
                        }
                    case .background:
                        Task { await Telemetry.flushWithFreshToken() }
                    default:
                        break
                    }
                }
        }
    }
}
