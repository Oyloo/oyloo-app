import Foundation

public struct MoneyLine: Sendable, Equatable {
    public let name: String
    public let balanceCents: Int
    /// The unfinished, unarchived goal closest to completion.
    public let nextGoal: MoneyGoal?

    public init(name: String, balanceCents: Int, nextGoal: MoneyGoal?) {
        self.name = name
        self.balanceCents = balanceCents
        self.nextGoal = nextGoal
    }
}

/// The Today screen's content, computed from whatever the section calls
/// returned. Each input may be missing (not loaded yet, not allowed).
public struct TodaySummary: Sendable, Equatable {
    public static let taskLimit = 5

    public let tasks: [TaskItem]
    public let openTaskCount: Int
    public let money: [MoneyLine]

    public static func make(tasks: TasksOverview?, money: MoneyOverview?) -> TodaySummary {
        let open = tasks?.todos.filter(\.isOpen) ?? []
        return TodaySummary(
            tasks: Array(open.prefix(taskLimit)),
            openTaskCount: open.count,
            money: moneyLines(money)
        )
    }

    private static func moneyLines(_ money: MoneyOverview?) -> [MoneyLine] {
        switch money {
        case .none:
            return []
        case let .kid(_, kid):
            return [line(kid)]
        case let .parent(_, kids, _):
            return kids.map(line)
        }
    }

    private static func line(_ kid: KidMoney) -> MoneyLine {
        let next = kid.goals.filter(\.isActive).min { $0.remainingCents < $1.remainingCents }
        return MoneyLine(name: kid.displayName, balanceCents: kid.balanceCents, nextGoal: next)
    }
}

/// Newest first, at most `count`.
public func latest<T>(_ items: [T], count: Int, date: KeyPath<T, Date>) -> [T] {
    Array(items.sorted { $0[keyPath: date] > $1[keyPath: date] }.prefix(count))
}
