import Foundation

/// The server's task views, in the order the web page shows them.
public enum TaskView: String, CaseIterable, Sendable, Identifiable {
    case today, overdue, next, waiting, someday, done
    public var id: String { rawValue }
}

/// How a due date reads next to a task.
public enum DueWording: Equatable, Sendable {
    case overdue(Int)
    case today
    case tomorrow
    case inDays(Int)
    case date(String)

    /// Within a week it counts days; further out it shows the date.
    public static func make(due: String, today: String) -> DueWording? {
        guard let d = day(due), let t = day(today) else { return nil }
        let diff = Calendar(identifier: .gregorian).dateComponents([.day], from: t, to: d).day ?? 0
        switch diff {
        case ..<0: return .overdue(-diff)
        case 0: return .today
        case 1: return .tomorrow
        case 2...7: return .inDays(diff)
        default: return .date(due)
        }
    }

    static func day(_ iso: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: iso), f.string(from: date) == iso else { return nil }
        return date
    }
}

/// Statuses a swipe can move a task to; completing is the row's own button.
public func statusActions(for status: String) -> [String] {
    switch status {
    case "done", "dropped": ["next"]
    default: ["next", "waiting", "someday", "dropped"].filter { $0 != status }
    }
}

/// A task before it is saved: what the parser suggests and the form edits.
public struct TaskDraft: Codable, Sendable, Equatable {
    public var title: String
    public var due: String?
    public var important: Bool
    public var circleId: String?
    public var tags: [String]

    public init(title: String, due: String?, important: Bool, circleId: String?, tags: [String]) {
        self.title = title
        self.due = due
        self.important = important
        self.circleId = circleId
        self.tags = tags
    }

    /// Body for `POST tasks`; empty optionals are left out.
    public var createBody: [String: Any] {
        var body: [String: Any] = [
            "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
            "important": important,
            "tags": tags
        ]
        if let due { body["due"] = due }
        if let circleId { body["circleId"] = circleId }
        return body
    }
}

/// Error codes of `POST tasks/parse`.
public enum TaskParseErrorCode: String, Sendable {
    case unavailable = "parse_unavailable"
    case failed = "parse_failed"
    case rateLimited = "rate_limited"
    case invalidInput = "invalid_input"
}
