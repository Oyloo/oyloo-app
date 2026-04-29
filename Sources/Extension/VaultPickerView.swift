import SwiftUI

/// Lightweight, type-erased preview of the share that's about to be
/// saved. Built synchronously from the extracted `SharedItem` so the
/// picker doesn't need to know about Codable shapes or attachments.
struct SharePreviewModel {
    let title: String
    let detail: String?
    let symbolName: String

    static let placeholder = SharePreviewModel(
        title: "Reading share…",
        detail: nil,
        symbolName: "hourglass"
    )

    static func from(_ item: SharedItem) -> SharePreviewModel {
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
            // Use the actual text content as the title rather than the
            // literal word "Text" — far more informative when scanning
            // the picker chip.
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

/// Two-button vault picker shown inside the share extension. Renders
/// the share preview at the top, then Life / Work as large buttons.
/// Disables actions while the upstream item is still being extracted.
struct VaultPickerView: View {
    let preview: SharePreviewModel
    let isProcessing: Bool
    let onSelect: (Vault) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                previewChip
                buttonRow
                if isProcessing { processingHint }
                Spacer(minLength: 0)
            }
            .padding(20)
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

    private var buttonRow: some View {
        HStack(spacing: 12) {
            vaultButton(.life, tint: .pink)
            vaultButton(.work, tint: .blue)
        }
    }

    private func vaultButton(_ vault: Vault, tint: Color) -> some View {
        Button { onSelect(vault) } label: {
            VStack(spacing: 10) {
                Image(systemName: vault.symbolName)
                    .font(.system(size: 36))
                    .foregroundStyle(tint)
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
