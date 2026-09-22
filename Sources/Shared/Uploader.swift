import Foundation

/// Ships outbox items to the configured endpoint: the missing last mile
/// between the share extension and any backend.
///
/// Attachments are streamed straight from disk (`upload(for:fromFile:)`), so a
/// long recording does not have to fit in memory. Items without an attachment
/// travel as a small JSON file, which keeps the receiving side to a single
/// verb. Shipped IDs are remembered, so re-running is safe and cheap.
public enum Uploader {
    public struct Report: Sendable {
        public var shipped = 0
        public var failed = 0
        public var skipped = 0

        public var summary: String {
            if shipped == 0 && failed == 0 { return "Nothing to send" }
            var parts = ["sent \(shipped)"]
            if failed > 0 { parts.append("failed \(failed)") }
            if skipped > 0 { parts.append("skipped \(skipped)") }
            return parts.joined(separator: ", ")
        }
    }

    public static func syncAll() async -> Report {
        var report = Report()
        guard SyncSettings.isConfigured else { return report }

        for item in SharedStore.readAll() where !SharedStore.isShipped(item.id) {
            do {
                try await ship(item)
                SharedStore.markShipped(item.id)
                report.shipped += 1
            } catch UploadError.nothingToSend {
                SharedStore.markShipped(item.id)
                report.skipped += 1
            } catch {
                report.failed += 1
            }
        }
        return report
    }

    // MARK: - One item

    private enum UploadError: Error {
        case nothingToSend
        case badResponse(Int)
        case noEndpoint
    }

    private static func ship(_ item: SharedItem) async throws {
        if let path = item.attachmentPath, let file = SharedStore.resolveAttachment(path) {
            let name = filename(for: item, fallbackExtension: file.pathExtension)
            try await put(fileURL: file, as: name, vault: item.vaultKey, contentType: item.mimeType,
                          publish: item.publish)
            return
        }
        guard item.text != nil || item.url != nil else { throw UploadError.nothingToSend }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(item)
        try await put(data: data, as: filename(for: item, fallbackExtension: "json"),
                      vault: item.vaultKey, contentType: "application/json")
    }

    private static func put(fileURL: URL, as name: String, vault: String, contentType: String?,
                            publish: Bool = false) async throws {
        var request = try await makeRequest(name: name, vault: vault, contentType: contentType,
                                            publish: publish)
        request.httpMethod = "PUT"
        let (_, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        try check(response)
    }

    private static func put(data: Data, as name: String, vault: String, contentType: String?) async throws {
        var request = try await makeRequest(name: name, vault: vault, contentType: contentType)
        request.httpMethod = "PUT"
        let (_, response) = try await URLSession.shared.upload(for: request, from: data)
        try check(response)
    }

    private static func makeRequest(
        name: String, vault: String, contentType: String?, publish: Bool = false
    ) async throws -> URLRequest {
        guard let url = SyncSettings.uploadURL(filename: name, vault: vault, publish: publish) else {
            throw UploadError.noEndpoint
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 600
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        // Browser sign-in first: on a family device each person ships under
        // their own account. A token typed into settings stays supported for
        // plainer endpoints that speak no OAuth.
        if let bearer = try? await OAuthClient.validAccessToken() {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        } else {
            let token = SyncSettings.token
            if !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }
        return request
    }

    private static func check(_ response: URLResponse) throws {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw UploadError.badResponse(code) }
    }

    /// Stable, readable name: vault, date and the original title when there is
    /// one, so files arrive sorted and recognisable rather than as raw UUIDs.
    private static func filename(for item: SharedItem, fallbackExtension: String) -> String {
        let stamp = stampFormatter.string(from: item.sharedAt)
        let ext = fallbackExtension.isEmpty ? "bin" : fallbackExtension
        var stem = (item.title ?? item.vaultKey)
        if let dot = stem.lastIndex(of: "."), stem.distance(from: dot, to: stem.endIndex) <= 5 {
            stem = String(stem[stem.startIndex..<dot])
        }
        let safe = stem.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) || " -_".unicodeScalars.contains($0)
                ? Character($0) : "_" }
            .prefix(60)
        let cleaned = String(safe).trimmingCharacters(in: .whitespaces)
        let base = cleaned.isEmpty ? item.vaultKey : cleaned
        return "\(item.vaultKey)-\(stamp)-\(base).\(ext)"
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
