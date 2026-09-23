import Foundation

/// Response shapes of the family app API. Only the fields the screens use
/// are decoded: anything the server adds later is ignored, so a newer server
/// never breaks an installed build.
public enum AppJSON {
    public static var decoder: JSONDecoder { JSONDecoder() }
}

public struct Me: Decodable, Sendable, Equatable {
    public let userId: String
    public let name: String?
    /// Sections the server lets this account see, e.g. "money", "tasks".
    public let sections: [String]

    public init(userId: String, name: String?, sections: [String]) {
        self.userId = userId
        self.name = name
        self.sections = sections
    }
}

public struct TaskItem: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let status: String
    public let important: Bool
    /// Due date as the server sends it, `YYYY-MM-DD`.
    public let due: String?
    public let circleId: String?
    /// P1…P4, computed by the server from importance and urgency.
    public let priority: String
    public let overdue: Bool

    public init(
        id: String, title: String, status: String, important: Bool, due: String?,
        circleId: String?, priority: String, overdue: Bool
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.important = important
        self.due = due
        self.circleId = circleId
        self.priority = priority
        self.overdue = overdue
    }

    public var isOpen: Bool { status != "done" && status != "dropped" }
}

public struct TasksOverview: Decodable, Sendable, Equatable {
    public let today: String
    public let view: String
    public let counts: [String: Int]
    public let todos: [TaskItem]

    public init(today: String, view: String, counts: [String: Int], todos: [TaskItem]) {
        self.today = today
        self.view = view
        self.counts = counts
        self.todos = todos
    }
}

public struct MoneyGoal: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let title: String
    public let targetCents: Int
    public let savedCents: Int
    public let percent: Int
    public let achieved: Bool
    public let archived: Bool

    public init(
        id: Int, title: String, targetCents: Int, savedCents: Int, percent: Int,
        achieved: Bool, archived: Bool
    ) {
        self.id = id
        self.title = title
        self.targetCents = targetCents
        self.savedCents = savedCents
        self.percent = percent
        self.achieved = achieved
        self.archived = archived
    }

    public var remainingCents: Int { max(0, targetCents - savedCents) }
    public var isActive: Bool { !achieved && !archived }
}

public struct KidMoney: Decodable, Sendable, Equatable, Identifiable {
    public let userId: String
    public let displayName: String
    public let hasAccounts: Bool
    public let balanceCents: Int
    public let balanceAsOf: String?
    public let freeCents: Int
    public let goals: [MoneyGoal]

    public init(
        userId: String, displayName: String, hasAccounts: Bool, balanceCents: Int,
        balanceAsOf: String?, freeCents: Int, goals: [MoneyGoal]
    ) {
        self.userId = userId
        self.displayName = displayName
        self.hasAccounts = hasAccounts
        self.balanceCents = balanceCents
        self.balanceAsOf = balanceAsOf
        self.freeCents = freeCents
        self.goals = goals
    }

    public var id: String { userId }
}

public struct MoneyMember: Decodable, Sendable, Equatable {
    public let userId: String
    public let role: String
    public let displayName: String

    public init(userId: String, role: String, displayName: String) {
        self.userId = userId
        self.role = role
        self.displayName = displayName
    }
}

/// A child sees their own money; a parent sees every child. The server says
/// which by `role`; any other role is a contract break and fails to decode.
public enum MoneyOverview: Decodable, Sendable, Equatable {
    case kid(me: MoneyMember, kid: KidMoney)
    case parent(me: MoneyMember, kids: [KidMoney])

    private enum CodingKeys: String, CodingKey { case role, me, kid, kids }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let me = try c.decode(MoneyMember.self, forKey: .me)
        switch try c.decode(String.self, forKey: .role) {
        case "kid":
            self = .kid(me: me, kid: try c.decode(KidMoney.self, forKey: .kid))
        case "parent":
            self = .parent(me: me, kids: try c.decode([KidMoney].self, forKey: .kids))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .role, in: c, debugDescription: "unknown money role"
            )
        }
    }
}
