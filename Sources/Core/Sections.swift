/// What the app can show. Today and Settings are always there; the rest
/// only when the server lists them for this account.
public enum AppSection: String, CaseIterable, Sendable, Identifiable {
    case today, money, tasks, captures, settings

    public var id: String { rawValue }
}

/// Before the first successful `me` the app does not know the account's
/// sections; capturing is what worked before this app had sections, so it
/// stays available offline from the very first launch.
public func visibleSections(me: Me?) -> [AppSection] {
    guard let me else { return [.today, .captures, .settings] }
    let serverSide: [AppSection] = [.money, .tasks, .captures]
    return [.today] + serverSide.filter { me.sections.contains($0.rawValue) } + [.settings]
}
