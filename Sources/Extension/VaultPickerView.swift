import SwiftUI

/// Lightweight, type-erased preview of the share that's about to be
/// saved. Built synchronously from the extracted `SharedItem` so the
/// picker doesn't need to know about Codable shapes or attachments.
struct SharePreviewModel {
    let title: String
    let detail: String?
    let symbolName: String
    var isAudio = false

    static let placeholder = SharePreviewModel(
        title: "Reading share…",
        detail: nil,
        symbolName: "hourglass"
    )

    static func from(_ item: SharedItem) -> SharePreviewModel {
        if item.isAudio {
            return SharePreviewModel(
                title: item.title ?? "Recording",
                detail: item.mimeType,
                symbolName: "waveform",
                isAudio: true
            )
        }
        if item.isImage {
            return SharePreviewModel(
                title: item.title ?? "Image",
                detail: item.mimeType,
                symbolName: "photo.fill"
            )
        }
        if item.isFile {
            return SharePreviewModel(
                title: item.title ?? "File",
                detail: item.mimeType,
                symbolName: "doc.fill"
            )
        }
        if let url = item.url {
            let host = URL(string: url)?.host ?? url
            return SharePreviewModel(
                title: item.title ?? host,
                detail: url,
                symbolName: "globe"
            )
        }
        if let text = item.text {
            let snippet = String(text.prefix(80))
            return SharePreviewModel(
                title: item.title ?? snippet,
                detail: item.title != nil ? text : nil,
                symbolName: "quote.opening"
            )
        }
        return SharePreviewModel(
            title: "Share",
            detail: nil,
            symbolName: "square.and.arrow.up"
        )
    }
}

/// Vault picker shown inside the share extension. Renders the share
/// preview at the top, then one button per user-defined vault. Empty
/// state when the user has not configured any vault yet.
struct VaultPickerView: View {
    let preview: SharePreviewModel
    let isProcessing: Bool
    let onSelect: (Vault, Bool) -> Void
    let onCancel: () -> Void
    @Bindable var store: VaultStore
    /// Recordings can be sent on as a podcast episode; the server keeps it a
    /// private draft first, so this is a wish, not an instant publication.
    @State private var publish = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let landscape = geometry.size.width > geometry.size.height && geometry.size.width >= 640
                Group {
                    if landscape {
                        landscapeLayout
                    } else {
                        portraitLayout
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .navigationTitle("Save share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
            }
            .background(.regularMaterial)
        }
    }

    private var portraitLayout: some View {
        VStack(alignment: .leading, spacing: 20) {
            previewChip
            publishToggle
            if store.vaults.isEmpty {
                emptyState
            } else {
                ScrollView {
                    buttonGrid(minimum: 140)
                }
            }
            if isProcessing { processingHint }
            Spacer(minLength: 0)
        }
    }

    private var landscapeLayout: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                previewChip
                publishToggle
                if isProcessing { processingHint }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: 300)

            if store.vaults.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    buttonGrid(minimum: 124)
                }
            }
        }
    }

    private var previewChip: some View {
        HStack(spacing: 12) {
            Image(systemName: preview.symbolName)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(.thinMaterial, in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(preview.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let detail = preview.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    @ViewBuilder
    private var publishToggle: some View {
        if preview.isAudio {
            Toggle(isOn: $publish) {
                Label("Podcast episode", systemImage: "mic.fill")
            }
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No vaults configured")
                .font(.headline)
            Text("Open the Oyloo app and add at least one vault, then come back to save this share.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private func buttonGrid(minimum: CGFloat) -> some View {
        // Adaptive grid handles 1, 2, 3, 4+ vaults gracefully.
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: minimum), spacing: 12)
        ], spacing: 12) {
            ForEach(store.vaults) { vault in
                vaultButton(vault)
            }
        }
    }

    private func vaultButton(_ vault: Vault) -> some View {
        Button { onSelect(vault, preview.isAudio && publish) } label: {
            VStack(spacing: 10) {
                Image(systemName: vault.symbolName)
                    .font(.system(size: 36))
                    .foregroundStyle(vault.tintColor)
                Text(vault.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding(8)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .opacity(isProcessing ? 0.5 : 1.0)
    }

    private var processingHint: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Reading share…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
