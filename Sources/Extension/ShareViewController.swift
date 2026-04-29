import UIKit
import SwiftUI
import UniformTypeIdentifiers
import LinkPresentation

/// Share extension hosting a vault picker over a SwiftUI view. The
/// host UIViewController extracts the share's richest single attachment
/// in the background while the picker is presented; once the user
/// taps a vault button the staged item is stamped with the chosen
/// `vaultKey` and appended to the matching outbox file.
@objc(ShareViewController)
final class ShareViewController: UIViewController {
    /// Initial preview built synchronously from the type identifiers
    /// we can see before any provider callback fires. Replaced once
    /// extraction finishes.
    private var initialPreview: SharePreviewModel = .placeholder

    /// Fully extracted item, awaiting a vault stamp. `nil` until
    /// extraction completes; if the user taps a vault before that
    /// arrives, the choice is parked in `pendingVault` and applied on
    /// arrival.
    private var stagedItem: SharedItem?
    private var pendingVault: Vault?

    /// `false` until extraction completes — drives the picker's
    /// "Reading share…" hint and disables the buttons.
    private var isExtracting: Bool = true

    /// Read fresh from App Group UserDefaults at extension launch so
    /// new vaults added in the container app appear without re-install.
    private let vaultStore = VaultStore()

    private var hostingController: UIHostingController<VaultPickerView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        initialPreview = detectInitialPreview()
        presentPicker()
        extractItem { [weak self] item in
            DispatchQueue.main.async {
                self?.stagingDidComplete(with: item)
            }
        }
    }

    // MARK: - Picker host

    private func presentPicker() {
        let host = UIHostingController(rootView: makePickerView())
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        hostingController = host
    }

    private func refreshPicker() {
        hostingController?.rootView = makePickerView()
    }

    private func makePickerView() -> VaultPickerView {
        let preview = stagedItem.map(SharePreviewModel.from) ?? initialPreview
        return VaultPickerView(
            preview: preview,
            isProcessing: isExtracting,
            onSelect: { [weak self] vault in self?.handleSelect(vault: vault) },
            onCancel: { [weak self] in self?.cancel() },
            store: vaultStore
        )
    }

    // MARK: - Picker callbacks

    private func handleSelect(vault: Vault) {
        if let item = stagedItem {
            commitAndComplete(item: item, vault: vault)
            return
        }
        // Extraction is still running — park the choice; it'll be
        // applied as soon as `stagingDidComplete(with:)` fires.
        pendingVault = vault
    }

    private func stagingDidComplete(with item: SharedItem?) {
        isExtracting = false
        stagedItem = item
        if let pending = pendingVault, let item {
            commitAndComplete(item: item, vault: pending)
            return
        }
        if item == nil && pendingVault != nil {
            // User chose a vault but extraction yielded nothing —
            // there's nothing to save. Cancel the host request.
            cancel()
            return
        }
        refreshPicker()
    }

    private func commitAndComplete(item: SharedItem, vault: Vault) {
        SharedStore.append(item.with(vaultKey: vault.key))
        ShareLog.write("committed to vault key=\(vault.key) name=\(vault.displayName)")
        complete()
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func cancel() {
        let cancelError = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        extensionContext?.cancelRequest(withError: cancelError)
    }

    // MARK: - Initial preview detection

    /// Build a best-guess preview from the providers' type identifiers
    /// without loading any data. Lets the picker render something
    /// useful before extraction completes.
    private func detectInitialPreview() -> SharePreviewModel {
        let providers = (extensionContext?.inputItems.first as? NSExtensionItem)?.attachments ?? []
        if providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            return SharePreviewModel(title: "Reading link…", detail: nil, symbolName: "globe")
        }
        if providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            return SharePreviewModel(title: "Reading file…", detail: nil, symbolName: "doc.fill")
        }
        if providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            return SharePreviewModel(title: "Reading image…", detail: nil, symbolName: "photo.fill")
        }
        if providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.text.identifier) }) {
            return SharePreviewModel(title: "Reading text…", detail: nil, symbolName: "quote.opening")
        }
        return .placeholder
    }

    // MARK: - Extraction

    private func extractItem(completion: @escaping (SharedItem?) -> Void) {
        guard
            let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let providers = item.attachments, !providers.isEmpty
        else {
            ShareLog.write("share triggered but no providers — completing as no-op")
            completion(nil)
            return
        }
        let fallbackTitle = item.attributedTitle?.string ?? item.attributedContentText?.string

        var debug = ["--- share triggered ---"]
        debug.append("attributedTitle=\(item.attributedTitle?.string ?? "<nil>")")
        debug.append("attributedContentText=\(item.attributedContentText?.string ?? "<nil>")")
        for (i, p) in providers.enumerated() {
            debug.append("provider[\(i)] types=[\(p.registeredTypeIdentifiers.joined(separator: ","))]")
        }
        ShareLog.write(debug.joined(separator: " | "))

        let log: (SharedItem?) -> SharedItem? = { item in
            if let item {
                ShareLog.write("extracted: vaultKey=<picker>, url=\(item.url ?? "<nil>"), title=\(item.title ?? "<nil>"), text=\(item.text?.prefix(60) ?? "<nil>"), attachmentPath=\(item.attachmentPath ?? "<nil>"), mimeType=\(item.mimeType ?? "<nil>")")
            } else {
                ShareLog.write("extracted: <nil> — extractor returned no item")
            }
            return item
        }
        let wrap: (@escaping (SharedItem?) -> Void) -> (SharedItem?) -> Void = { upstream in
            return { item in upstream(log(item)) }
        }

        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            ShareLog.write("dispatcher: URL")
            let siblings = providers.filter { $0 !== provider }
            extractURL(provider, siblingProviders: siblings, fallbackTitle: fallbackTitle, completion: wrap(completion))
            return
        }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            ShareLog.write("dispatcher: fileURL")
            extractFile(provider, fallbackTitle: fallbackTitle, completion: wrap(completion))
            return
        }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            ShareLog.write("dispatcher: image")
            extractImage(provider, fallbackTitle: fallbackTitle, completion: wrap(completion))
            return
        }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.text.identifier) }) {
            ShareLog.write("dispatcher: text")
            extractText(provider, fallbackTitle: fallbackTitle, completion: wrap(completion))
            return
        }
        ShareLog.write("dispatcher: <none matched>")
        completion(nil)
    }

    private func extractImage(_ provider: NSItemProvider, fallbackTitle: String?, completion: @escaping (SharedItem?) -> Void) {
        provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { value, _ in
            var data: Data?
            var ext = "jpg"

            if let url = value as? URL {
                guard url.isFileURL else {
                    completion(nil)
                    return
                }
                data = try? Data(contentsOf: url)
                if !url.pathExtension.isEmpty { ext = url.pathExtension.lowercased() }
            } else if let img = value as? UIImage {
                data = img.jpegData(compressionQuality: 0.85)
                ext = "jpg"
            } else if let raw = value as? Data {
                data = raw
            }

            guard let data, let path = SharedStore.saveAttachment(data, fileExtension: ext) else {
                completion(nil)
                return
            }
            let mime = Self.mimeType(forExt: ext) ?? "image/\(ext)"
            completion(SharedItem(
                title: fallbackTitle,
                attachmentPath: path,
                mimeType: mime
            ))
        }
    }

    private func extractURL(_ provider: NSItemProvider, siblingProviders: [NSItemProvider], fallbackTitle: String?, completion: @escaping (SharedItem?) -> Void) {
        provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { value, _ in
            var urlString: String?
            var capturedURL: URL?
            if let url = value as? URL {
                capturedURL = url
                urlString = url.absoluteString
            } else if let s = value as? String {
                urlString = s
                capturedURL = URL(string: s)
            }

            guard let urlString else {
                completion(nil)
                return
            }
            let host = capturedURL?.host

            Self.loadFirstText(from: siblingProviders) { siblingText in
                guard let url = capturedURL else {
                    let title = Self.bestTitle(
                        candidates: [siblingText, fallbackTitle],
                        urlString: urlString,
                        host: host
                    )
                    completion(SharedItem(url: urlString, title: title))
                    return
                }
                let metadata = LPMetadataProvider()
                metadata.timeout = 8
                metadata.startFetchingMetadata(for: url) { meta, _ in
                    let title = Self.bestTitle(
                        candidates: [meta?.title, siblingText, fallbackTitle],
                        urlString: urlString,
                        host: host
                    )
                    completion(SharedItem(url: urlString, title: title))
                }
            }
        }
    }

    private static func loadFirstText(from providers: [NSItemProvider], completion: @escaping (String?) -> Void) {
        guard let first = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.text.identifier) }) else {
            completion(nil)
            return
        }
        first.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { value, _ in
            completion(value as? String)
        }
    }

    private func extractFile(_ provider: NSItemProvider, fallbackTitle: String?, completion: @escaping (SharedItem?) -> Void) {
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { value, _ in
            guard let url = value as? URL, url.isFileURL,
                  let data = try? Data(contentsOf: url) else {
                completion(nil)
                return
            }
            let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension.lowercased()
            let filename = url.lastPathComponent
            guard let path = SharedStore.saveAttachment(data, fileExtension: ext) else {
                completion(nil)
                return
            }
            let mime = Self.mimeType(forExt: ext) ?? "application/octet-stream"
            completion(SharedItem(
                title: fallbackTitle ?? filename,
                attachmentPath: path,
                mimeType: mime
            ))
        }
    }

    private func extractText(_ provider: NSItemProvider, fallbackTitle: String?, completion: @escaping (SharedItem?) -> Void) {
        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { value, _ in
            guard let raw = value as? String else {
                completion(nil)
                return
            }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                completion(nil)
                return
            }
            if let urlString = Self.detectURL(in: text),
               let url = URL(string: urlString),
               Self.textIsPrimarilyURL(text: text, urlString: urlString) {
                let titleFromText = Self.titleByStrippingURL(text, urlString: urlString)
                let metadata = LPMetadataProvider()
                metadata.timeout = 8
                metadata.startFetchingMetadata(for: url) { meta, _ in
                    let title = Self.bestTitle(
                        candidates: [meta?.title, titleFromText, fallbackTitle],
                        urlString: urlString,
                        host: url.host
                    )
                    completion(SharedItem(url: urlString, title: title))
                }
                return
            }
            completion(SharedItem(title: fallbackTitle, text: text))
        }
    }

    private static func detectURL(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        return detector.firstMatch(in: text, range: range)?.url?.absoluteString
    }

    private static func textIsPrimarilyURL(text: String, urlString: String) -> Bool {
        let leftover = titleByStrippingURL(text, urlString: urlString) ?? ""
        return leftover.count < 200
    }

    private static func titleByStrippingURL(_ text: String, urlString: String) -> String? {
        var stripped = text
        if let r = stripped.range(of: urlString) {
            stripped.removeSubrange(r)
        }
        let separators = CharacterSet(charactersIn: " \n\t-—–|·•:")
        stripped = stripped.trimmingCharacters(in: separators)
        return stripped.isEmpty ? nil : stripped
    }

    // MARK: - Helpers

    private static func bestTitle(candidates: [String?], urlString: String, host: String?) -> String? {
        for raw in candidates.compactMap({ $0 }) {
            if let cleaned = sanitiseTitle(raw, urlString: urlString) {
                return cleaned
            }
        }
        return host
    }

    private static func sanitiseTitle(_ raw: String?, urlString: String) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        var stripped = raw
        if let r = stripped.range(of: urlString) {
            stripped.removeSubrange(r)
        }
        let separators = CharacterSet(charactersIn: " \n\t-—–|·•:")
        stripped = stripped.trimmingCharacters(in: separators)
        if stripped.isEmpty { return nil }
        if stripped == urlString { return nil }
        if stripped.range(of: "https?://", options: .regularExpression) != nil { return nil }
        return stripped
    }

    private static func mimeType(forExt ext: String) -> String? {
        UTType(filenameExtension: ext.lowercased())?.preferredMIMEType
    }
}
