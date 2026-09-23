import Foundation
import Observation

/// Everything the Today screen and the sections read, created once for the
/// app so a tab switch never refetches or loses what is on screen.
@MainActor
@Observable
final class FamilyData {
    let me = CachedResource<Me>(key: AppAPI.key("me")) { try await AppAPI.me() }
    let tasksToday = CachedResource<TasksOverview>(
        key: AppAPI.key("tasks", query: [URLQueryItem(name: "view", value: "today")])
    ) { try await AppAPI.tasks(view: "today") }
    @ObservationIgnored private var taskViews: [String: CachedResource<TasksOverview>] = [:]

    /// One resource per view and tag, kept so switching back shows it at once.
    func tasks(view: TaskView, tag: String?) -> CachedResource<TasksOverview> {
        if view == .today, tag == nil { return tasksToday }
        let query = AppAPI.tasksQuery(view: view.rawValue, tag: tag)
        let key = AppAPI.key("tasks", query: query)
        if let existing = taskViews[key] { return existing }
        let made = CachedResource<TasksOverview>(key: key) {
            try await AppAPI.tasks(view: view.rawValue, tag: tag)
        }
        taskViews[key] = made
        return made
    }

    let money = CachedResource<MoneyOverview>(key: AppAPI.key("money")) { try await AppAPI.money() }
    let captures = CaptureFeed()

    var sections: [AppSection] { visibleSections(me: me.value) }

    /// `me` first: it decides which of the others this account may call.
    func refreshAll() async {
        await me.refresh()
        let allowed = sections
        await withTaskGroup(of: Void.self) { group in
            if allowed.contains(.tasks) { group.addTask { await self.tasksToday.refresh() } }
            if allowed.contains(.money) { group.addTask { await self.money.refresh() } }
            if allowed.contains(.captures) { group.addTask { await self.captures.refresh() } }
        }
    }
}
