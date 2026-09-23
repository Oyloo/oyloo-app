import Foundation

/// Decides which keychain reads are worth a log line.
///
/// Settings live in the keychain on a free team, and ordinary work reads the
/// same few keys over and over: one share read the server address a dozen
/// times, and every read became a record, burying the ten lines that mattered
/// under thirty that said the same thing. The question these lines answer is
/// "can this process read this key, and did that change" — so a key is
/// reported the first time, again when its outcome changes, and always when
/// the read fails for a reason other than the item simply not existing.
public final class KeychainReadReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var lastStatus: [String: Int32] = [:]

    public init() {}

    /// errSecSuccess and errSecItemNotFound are the two ordinary answers.
    private static let ordinary: Set<Int32> = [0, -25300]

    public func shouldReport(key: String, status: Int32) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard Self.ordinary.contains(status) else { return true }
        if lastStatus[key] == status { return false }
        lastStatus[key] = status
        return true
    }
}
