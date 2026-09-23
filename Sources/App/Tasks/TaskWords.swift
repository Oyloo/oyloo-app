import SwiftUI

func viewLabel(_ view: TaskView, count: Int?) -> String {
    let name: String = switch view {
    case .today: String(localized: "Today")
    case .overdue: String(localized: "Overdue")
    case .next: String(localized: "Next")
    case .waiting: String(localized: "Waiting")
    case .someday: String(localized: "Someday")
    case .done: String(localized: "Done")
    }
    guard let count else { return name }
    return "\(name) · \(count)"
}

func statusLabel(_ status: String) -> String {
    switch status {
    case "next": String(localized: "Next")
    case "waiting": String(localized: "Waiting")
    case "someday": String(localized: "Someday")
    case "dropped": String(localized: "Drop")
    default: status
    }
}

func statusTint(_ status: String) -> Color {
    switch status {
    case "dropped": .red
    case "waiting": .orange
    case "someday": .gray
    default: .blue
    }
}

func dueText(_ wording: DueWording) -> String {
    switch wording {
    case .today: String(localized: "due today")
    case .tomorrow: String(localized: "due tomorrow")
    case let .inDays(n): String(localized: "due in \(n) days")
    case let .overdue(n): String(localized: "\(n) days overdue")
    case let .date(iso):
        DueWording.day(iso).map { String(localized: "due \($0.formatted(.dateTime.day().month()))") } ?? iso
    }
}

/// The person-facing reason parsing did not fill the form.
func parseFailureText(_ error: Error) -> String {
    if case let AppAPI.Failure.server(code, message) = error {
        switch TaskParseErrorCode(rawValue: code) {
        case .unavailable: return String(localized: "Parsing is not set up on the server yet. The phrase became the title.")
        case .failed: return String(localized: "The phrase could not be parsed. It became the title.")
        case .rateLimited: return String(localized: "Too many phrases this hour. The phrase became the title.")
        case .invalidInput: return String(localized: "The phrase is empty or too long.")
        case .none: return message
        }
    }
    return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
}
