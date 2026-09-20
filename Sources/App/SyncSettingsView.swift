import SwiftUI

/// Where captures are shipped. Values live on the device only; this repo
/// carries no server of its own.
struct SyncSettingsView: View {
    @State private var baseURL = SyncSettings.baseURL
    @State private var token = SyncSettings.token
    @State private var isSending = false
    @State private var status: String?

    var body: some View {
        Form {
            Section {
                TextField("https://host/path/", text: $baseURL)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: baseURL) { _, new in SyncSettings.baseURL = new }
                SecureField("Token (optional)", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: token) { _, new in SyncSettings.token = new }
            } header: {
                Text("Server")
            } footer: {
                Text("Each capture is sent as PUT <server>upload?name=<filename> with the file as the body. A token, when set, travels as a bearer header.")
            }

            Section {
                Button {
                    Task { await send() }
                } label: {
                    HStack {
                        Text(isSending ? "Sending…" : "Send now")
                        if isSending {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isSending || !SyncSettings.isConfigured)
                if let status {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Captures are also sent automatically when the app opens. Anything the server rejects stays in the outbox and is retried later.")
            }
        }
        .navigationTitle("Sync")
    }

    private func send() async {
        isSending = true
        let report = await Uploader.syncAll()
        status = report.summary
        isSending = false
    }
}
