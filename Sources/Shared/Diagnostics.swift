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
/// Only counts, flags, OSStatus codes and fixed key names are marked `public`.
/// Anything the user typed or shared — vault names, titles, text, attachment
/// paths, the server address — is `private` and shows as <private> without a
/// logging profile. Nothing here logs a token or a capture body at all.
public enum Diagnostics {
    public static let subsystem = "com.oyloo.life"

    public static let storage = Logger(subsystem: subsystem, category: "storage")
    public static let share = Logger(subsystem: subsystem, category: "share")
    public static let sync = Logger(subsystem: subsystem, category: "sync")

    /// "app" or "extension", so one syslog stream shows which process spoke.
    public static let process: String = Bundle.main.bundlePath.hasSuffix(".appex") ? "extension" : "app"
}
