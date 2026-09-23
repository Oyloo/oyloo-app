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
