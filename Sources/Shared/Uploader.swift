import Foundation
import os

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
        /// Kind of the last failure, safe for a public log: an HTTP status,
        /// a URLError code or an error type name; never a URL or a title.
        public var lastFailure: String?

        public var summary: String {
            if shipped == 0 && failed == 0 { return "Nothing to send" }
            var parts = ["sent \(shipped)"]
            if failed > 0 { parts.append("failed \(failed)") }
            if skipped > 0 { parts.append("skipped \(skipped)") }
            return parts.joined(separator: ", ")
        }

        /// How the last request was authorised: oauth, static, none, or the
        /// kind of OAuth failure that led to the fallback.
        public var auth: String = "-"

        /// One line of counts and codes for the diagnostics relay.
        public var diagnostics: String {
            "sent=\(shipped) failed=\(failed) skipped=\(skipped) lastFailure=\(lastFailure ?? "-") auth=\(auth)"
        }
    }

    /// Set by `makeRequest`, read into the report: the extension's own log
    /// needs a cable, the relayed report does not.
    private static var lastAuth = "-"

    public static func syncAll() async -> Report {
        var report = Report()
        guard SyncSettings.isConfigured else {
            Diagnostics.sync.notice("sync process=\(Diagnostics.process, privacy: .public) skipped: not configured")
            return report
        }

        let pending = SharedStore.readAll().filter { !SharedStore.isShipped($0.id) }
        Diagnostics.sync.notice(
            "sync start process=\(Diagnostics.process, privacy: .public) pending=\(pending.count, privacy: .public)"
        )
        for item in pending {
            do {
                try await ship(item)
                SharedStore.markShipped(item.id)
                report.shipped += 1
                Diagnostics.sync.notice("sync item process=\(Diagnostics.process, privacy: .public) result=shipped")
            } catch UploadError.nothingToSend {
                SharedStore.markShipped(item.id)
                report.skipped += 1
                Diagnostics.sync.notice("sync item process=\(Diagnostics.process, privacy: .public) result=skipped")
            } catch {
                report.failed += 1
                let kind = failureKind(error)
                report.lastFailure = kind
                Diagnostics.sync.error(
                    "sync item process=\(Diagnostics.process, privacy: .public) result=failed kind=\(kind, privacy: .public)"
                )
            }
        }
        report.auth = lastAuth
        Diagnostics.sync.notice(
            "sync done process=\(Diagnostics.process, privacy: .public) \(report.diagnostics, privacy: .public)"
        )
        return report
    }

    private static func failureKind(_ error: Error) -> String {
        switch error {
        case UploadError.badResponse(let code): return "http\(code)"
        case UploadError.noEndpoint: return "noEndpoint"
        case UploadError.nothingToSend: return "nothingToSend"
        case let urlError as URLError: return "urlError\(urlError.code.rawValue)"
        default: return String(describing: type(of: error))
        }
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
        do {
            let bearer = try await OAuthClient.validAccessToken()
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
            lastAuth = "oauth"
            Diagnostics.sync.notice("auth process=\(Diagnostics.process, privacy: .public) source=oauth")
        } catch {
            lastAuth = "oauthFailed:" + String(describing: error).prefix(40)
            // Which way the sign-in failed matters more than the upload's
            // eventual 401: the extension reads the token from the shared
            // keychain, and "not signed in" there while the app is signed in
            // means the two do not share it.
            Diagnostics.sync.error(
                """
                auth process=\(Diagnostics.process, privacy: .public) oauth failed \
                kind=\(String(describing: error).prefix(40), privacy: .public) \
                detail=\(error.localizedDescription, privacy: .private)
                """
            )
            let token = SyncSettings.token
            if !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                lastAuth += "/static"
                Diagnostics.sync.notice("auth process=\(Diagnostics.process, privacy: .public) source=static")
            } else {
                lastAuth += "/none"
                Diagnostics.sync.notice("auth process=\(Diagnostics.process, privacy: .public) source=none")
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
