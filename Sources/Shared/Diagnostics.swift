import Foundation
import os

/// Unified-logging channel shared by the app and the share extension.
///
/// The extension cannot write `ShareLog` without an App Group container, and
/// on a free provisioning team there is none — so the only diagnostic channel
/// that works in both processes is the system log. Read it from a Mac with the
/// device attached:
///
///     idevicesyslog -p Oyloo -p ShareToOyloo
///     # or, narrower:
///     idevicesyslog | grep com.oyloo.life
///
/// Messages are marked `public` on purpose: these are vault names, key names
/// and OSStatus codes, not captures or tokens. Nothing here logs a token, a
/// capture body or a file the user shared.
public enum Diagnostics {
    public static let subsystem = "com.oyloo.life"

    public static let storage = Logger(subsystem: subsystem, category: "storage")
    public static let share = Logger(subsystem: subsystem, category: "share")
    public static let sync = Logger(subsystem: subsystem, category: "sync")

    /// "app" or "extension", so one syslog stream shows which process spoke.
    public static let process: String = Bundle.main.bundlePath.hasSuffix(".appex") ? "extension" : "app"
}
