import Foundation

/// How old cached data is, as a value the view turns into words.
public enum Freshness: Sendable, Equatable {
    case justNow
    case minutes(Int)
    case hours(Int)
    case days(Int)

    public static func of(_ date: Date, now: Date = Date()) -> Freshness {
        let seconds = Int(max(0, now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return .justNow
        case ..<3600: return .minutes(seconds / 60)
        case ..<86400: return .hours(seconds / 3600)
        default: return .days(seconds / 86400)
        }
    }
}
