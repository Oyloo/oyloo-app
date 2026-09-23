import Foundation
import OpenTelemetryApi
import OpenTelemetryProtocolExporterCommon
import OpenTelemetryProtocolExporterHttp
import OpenTelemetrySdk
import UIKit
import os

/// Where a record belongs. The same three channels as `Diagnostics`, so one
/// line of code produces one system-log line and one exported record under
/// the same name.
public enum TelemetryScope: String, Sendable {
    case storage
    case share
    case sync

    var logger: os.Logger {
        switch self {
        case .storage: Diagnostics.storage
        case .share: Diagnostics.share
        case .sync: Diagnostics.sync
        }
    }
}

/// The only kinds of value an attribute may carry.
///
/// This is the privacy rule made into a type. Counts, flags and status codes
/// are safe by nature; a `String` is not, so the string case is deliberately
/// missing and every textual attribute goes through `.name`, which takes a
/// fixed name from this code base — never something the user typed.
public enum TelemetryValue: Sendable {
    case count(Int)
    case flag(Bool)
    case status(Int32)
    /// A fixed identifier from this source: an event kind, a result, an error
    /// case name. Never a title, a path, a vault name or a server address.
    case name(String)

    var attribute: AttributeValue {
        switch self {
        case .count(let value): .int(value)
        case .flag(let value): .bool(value)
        case .status(let value): .int(Int(value))
        case .name(let value): .string(value)
        }
    }

    var readable: String {
        switch self {
        case .count(let value): String(value)
        case .flag(let value): value ? "true" : "false"
        case .status(let value): String(value)
        case .name(let value): value
        }
    }
}

/// Telemetry that leaves the device, beside the system log that does not.
///
/// The share extension is the reason this exists. It runs in its own process
/// for a few seconds, on a free provisioning team, and its `os_log` output
/// needs a cable to read — so a share that fails on someone else's phone used
/// to be invisible. Records and spans go to the household collector through
/// the same server the captures do; the system log keeps working unchanged as
/// the local copy.
///
/// Everything here is best effort. A capture is never delayed or dropped
/// because telemetry could not be sent.
public enum Telemetry {
    public static let serviceName = "oyloo-ios"

    // MARK: - Lifecycle

    // Recursive: bootstrapping reads settings, reading settings logs, and
    // logging bootstraps. The cycle is real and it is fine — it just must not
    // deadlock on the way through.
    private static let lock = NSRecursiveLock()
    nonisolated(unsafe) private static var started = false
    nonisolated(unsafe) private static var loggerProvider: LoggerProviderSdk?
    nonisolated(unsafe) private static var tracerProvider: TracerProviderSdk?
    nonisolated(unsafe) private static var logProcessor: BatchLogRecordProcessor?
    nonisolated(unsafe) private static var spanProcessor: BatchSpanProcessor?
    nonisolated(unsafe) private static var bearer: String?
    nonisolated(unsafe) private static var exportFailed = false

    /// True when the last batch did not reach the server.
    ///
    /// The share extension asks before writing the keychain relay: with the
    /// collector reachable, repeating the line through the app's console is
    /// noise, and the relay exists only for the case where it is not.
    public static var lastExportFailed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return exportFailed
    }

    /// Reported by the transport after every attempt.
    static func recordExportOutcome(succeeded: Bool) {
        lock.lock()
        exportFailed = !succeeded
        lock.unlock()
    }

    /// Idempotent, and called by every `event`/`span`: nothing has to remember
    /// to bootstrap first, and a record emitted before an explicit start is
    /// not lost.
    public static func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        started = true

        // The SDK's own feedback goes through os_log as public text, and a
        // URLError's description carries the failing URL — the user's server
        // address. Route it to a private line instead.
        OpenTelemetry.registerFeedbackHandler { message in
            Diagnostics.sync.debug("telemetry sdk: \(message, privacy: .private)")
        }

        let resource = makeResource()
        let configuration = OtlpConfiguration(
            timeout: 15,
            // No gzip: the payload is kilobytes, and one less transformation
            // between here and the collector is one less thing to debug.
            compression: .none,
            exportAsJson: false,
            headersProvider: { authorizationHeaders() }
        )

        let logExporter = OtlpHttpLogExporter(
            endpoint: endpoint(for: "logs") ?? placeholderEndpoint,
            config: configuration,
            httpClient: TelemetryTransport(signal: "logs"),
            envVarHeaders: nil,
            // The transport owns retry through its spool; a second copy in
            // the exporter's memory queue would double every record.
            requeueOnFailure: false
        )
        let spanExporter = OtlpHttpTraceExporter(
            endpoint: endpoint(for: "traces") ?? placeholderEndpoint,
            config: configuration,
            httpClient: TelemetryTransport(signal: "traces"),
            envVarHeaders: nil,
            requeueOnFailure: false
        )

        // Two seconds rather than the default five: the share extension lives
        // for about as long as the sheet is open, and a batch that has already
        // gone needs no flush at all.
        let logs = BatchLogRecordProcessor(logRecordExporter: logExporter, scheduleDelay: 2)
        let spans = BatchSpanProcessor(spanExporter: spanExporter, scheduleDelay: 2)
        logProcessor = logs
        spanProcessor = spans

        let logger = LoggerProviderBuilder()
            .with(resource: resource)
            .with(processors: [logs])
            .build()
        let tracer = TracerProviderBuilder()
            .with(resource: resource)
            .add(spanProcessor: spans)
            .build()
        loggerProvider = logger
        tracerProvider = tracer
        OpenTelemetry.registerLoggerProvider(loggerProvider: logger)
        OpenTelemetry.registerTracerProvider(tracerProvider: tracer)
    }

    /// Only ever used as the exporter's birth value; every request is
    /// re-pointed by the transport, and one with no server fails there.
    private static let placeholderEndpoint = URL(string: "http://127.0.0.1:4318/v1/logs")!

    private static func makeResource() -> Resource {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        let device = UIDevice.current
        return Resource(attributes: [
            "service.name": .string(serviceName),
            "service.version": .string("\(short)+\(build)"),
            // Which of the two processes spoke. The extension is the whole
            // reason for exporting at all, and its records must be
            // distinguishable at a glance.
            "process": .string(Diagnostics.process),
            "os.name": .string(device.systemName),
            "os.version": .string(device.systemVersion),
            "device.model.identifier": .string(hardwareModel())
        ])
    }

    private static func hardwareModel() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }

    // MARK: - Address and authorisation

    /// The server's OTLP path for a signal, or nil when no server is set.
    /// Read fresh every time: the address lives in settings and may change.
    static func endpoint(for signal: String) -> URL? {
        guard SyncSettings.isConfigured else { return nil }
        return URL(string: SyncSettings.baseURL + "api/otlp/v1/" + signal)
    }

    private static func authorizationHeaders() -> [(String, String)]? {
        lock.lock()
        let token = bearer
        lock.unlock()
        guard let token else { return nil }
        return [("Authorization", "Bearer \(token)")]
    }

    /// Caches the access token the exporters sign with. The server accepts
    /// only the app's OAuth token here, so an unsigned batch is pointless —
    /// but it still spools, and the next refresh gets it out.
    public static func refreshAuthorization() async {
        let token = try? await OAuthClient.validAccessToken()
        lock.lock()
        bearer = token
        lock.unlock()
    }

    // MARK: - Records

    /// One event: a fixed name, a scope, and attributes that may only be
    /// counts, flags, status codes and fixed names (see `TelemetryValue`).
    public static func event(
        _ name: String,
        scope: TelemetryScope,
        severity: Severity = .info,
        _ attributes: [String: TelemetryValue] = [:]
    ) {
        let line = readableLine(name: name, attributes: attributes)
        // The local copy is written first and unconditionally. It is the
        // fallback the network cannot take away, and it also survives the
        // moment during bootstrap when there is no provider yet — which is
        // exactly when the storage and keychain lines are emitted.
        //
        // Public by construction: `TelemetryValue` admits nothing a user
        // typed. Anything private stays a direct `Diagnostics` call and never
        // becomes a record.
        if severity >= .error {
            scope.logger.error("\(line, privacy: .public)")
        } else {
            scope.logger.notice("\(line, privacy: .public)")
        }

        start()
        guard let provider = loggerProvider else { return }
        var mapped = attributes.mapValues(\.attribute)
        mapped["event.name"] = .string(name)
        provider.get(instrumentationScopeName: scope.rawValue)
            .logRecordBuilder()
            .setSeverity(severity)
            .setEventName(name)
            // The body repeats what the attributes hold: a logs backend shows
            // one readable line, and the attributes stay queryable.
            .setBody(.string(line))
            .setAttributes(mapped)
            .emit()
    }

    private static func readableLine(name: String, attributes: [String: TelemetryValue]) -> String {
        let pairs = attributes.keys.sorted().map { "\($0)=\(attributes[$0]!.readable)" }
        return ([name] + pairs).joined(separator: " ")
    }

    // MARK: - Spans

    /// Starts a span. Parents are passed explicitly rather than taken from
    /// the ambient context: the flows here cross `Task` boundaries, where the
    /// implicit context does not follow reliably.
    public static func span(_ name: String, scope: TelemetryScope = .share, parent: Span? = nil) -> Span {
        start()
        guard let provider = tracerProvider else {
            return DefaultTracer.instance.spanBuilder(spanName: name).startSpan()
        }
        let builder = provider
            .get(instrumentationName: scope.rawValue)
            .spanBuilder(spanName: name)
        if let parent {
            _ = builder.setParent(parent)
        } else {
            _ = builder.setNoParent()
        }
        let span = builder.startSpan()
        span.setAttribute(key: "process", value: Diagnostics.process)
        return span
    }

    /// Ends a span, marking it failed when a reason is given. The reason is a
    /// fixed kind — an HTTP status, an error case — never a message.
    public static func end(_ span: Span, failure: String? = nil, attributes: [String: TelemetryValue] = [:]) {
        for (key, value) in attributes {
            span.setAttribute(key: key, value: value.attribute)
        }
        if let failure {
            span.setAttribute(key: "failure.kind", value: failure)
            span.status = .error(description: failure)
        } else {
            span.status = .ok
        }
        span.end()
    }

    // MARK: - Flush

    /// Pushes whatever is batched, blocking up to `timeout`.
    ///
    /// The share extension must call this before it completes its request:
    /// the process is gone immediately afterwards, and an unflushed batch
    /// dies with it. Blocking is the point, so callers run it off the
    /// cooperative pool.
    public static func flush(timeout: TimeInterval = 6) {
        guard started else { return }
        logProcessor?.forceFlush(timeout: timeout)
        spanProcessor?.forceFlush(timeout: timeout)
    }

    /// Refreshes the token, then flushes. The token is what the server checks,
    /// and inside the extension it may have just been renewed for the upload.
    public static func flushWithFreshToken(timeout: TimeInterval = 6) async {
        await refreshAuthorization()
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                flush(timeout: timeout)
                continuation.resume()
            }
        }
    }
}
