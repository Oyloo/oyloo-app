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
    public let waitingOn: String?
    public let tags: [String]

    public init(
        id: String, title: String, status: String, important: Bool, due: String?,
        circleId: String?, priority: String, overdue: Bool,
        waitingOn: String? = nil, tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.important = important
        self.due = due
        self.circleId = circleId
        self.priority = priority
        self.overdue = overdue
        self.waitingOn = waitingOn
        self.tags = tags
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, status, important, due, circleId, priority, overdue, waitingOn, tags
    }

    /// Fields added after the foundation build fall back to empty values.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        status = try c.decode(String.self, forKey: .status)
        important = try c.decodeIfPresent(Bool.self, forKey: .important) ?? false
        due = try c.decodeIfPresent(String.self, forKey: .due)
        circleId = try c.decodeIfPresent(String.self, forKey: .circleId)
        priority = try c.decodeIfPresent(String.self, forKey: .priority) ?? "P4"
        overdue = try c.decodeIfPresent(Bool.self, forKey: .overdue) ?? false
        waitingOn = try c.decodeIfPresent(String.self, forKey: .waitingOn)
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
    }

    public var isOpen: Bool { status != "done" && status != "dropped" }
}

public struct TaskTag: Decodable, Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public let label: String
    public init(id: String, label: String) { self.id = id; self.label = label }
}

public struct TaskCircle: Decodable, Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public let label: String
    public init(id: String, label: String) { self.id = id; self.label = label }
}

public struct TasksOverview: Decodable, Sendable, Equatable {
    public let today: String
    public let view: String
    public let tag: String?
    public let counts: [String: Int]
    public let todos: [TaskItem]
    public let tags: [TaskTag]
    public let circles: [TaskCircle]

    public init(
        today: String, view: String, counts: [String: Int], todos: [TaskItem],
        tag: String? = nil, tags: [TaskTag] = [], circles: [TaskCircle] = []
    ) {
        self.today = today
        self.view = view
        self.tag = tag
        self.counts = counts
        self.todos = todos
        self.tags = tags
        self.circles = circles
    }

    private enum CodingKeys: String, CodingKey { case today, view, tag, counts, todos, tags, circles }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        today = try c.decode(String.self, forKey: .today)
        view = try c.decode(String.self, forKey: .view)
        tag = try c.decodeIfPresent(String.self, forKey: .tag)
        counts = try c.decodeIfPresent([String: Int].self, forKey: .counts) ?? [:]
        todos = try c.decode([TaskItem].self, forKey: .todos)
        tags = (try? c.decodeIfPresent([TaskTag].self, forKey: .tags)) ?? []
        circles = (try? c.decodeIfPresent([TaskCircle].self, forKey: .circles)) ?? []
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

public struct MonthSummary: Decodable, Sendable, Equatable {
    /// `YYYY-MM`.
    public let month: String
    public let receivedCents: Int
    public let spentCents: Int

    public init(month: String, receivedCents: Int, spentCents: Int) {
        self.month = month
        self.receivedCents = receivedCents
        self.spentCents = spentCents
    }
}

public struct PlaceTotal: Decodable, Sendable, Equatable {
    public let name: String
    public let cents: Int
    public let count: Int

    public init(name: String, cents: Int, count: Int) {
        self.name = name
        self.cents = cents
        self.count = count
    }
}

public struct FeedItem: Decodable, Sendable, Equatable {
    public let date: String
    public let label: String
    public let amountCents: Int
    /// "in", "out", "internal" or "other", as the server classifies it.
    public let kind: String

    public init(date: String, label: String, amountCents: Int, kind: String) {
        self.date = date
        self.label = label
        self.amountCents = amountCents
        self.kind = kind
    }
}

public struct UnassignedAccount: Decodable, Sendable, Equatable, Identifiable {
    public let identificationHash: String
    public let name: String?
    public let currency: String?
    public let product: String?
    public let txCount: Int
    public let lastActivity: String?

    public init(
        identificationHash: String, name: String?, currency: String?, product: String?,
        txCount: Int, lastActivity: String?
    ) {
        self.identificationHash = identificationHash
        self.name = name
        self.currency = currency
        self.product = product
        self.txCount = txCount
        self.lastActivity = lastActivity
    }

    public var id: String { identificationHash }
}

public struct KidMoney: Decodable, Sendable, Equatable, Identifiable {
    public let userId: String
    public let displayName: String
    public let hasAccounts: Bool
    public let balanceCents: Int
    public let balanceAsOf: String?
    public let freeCents: Int
    public let goals: [MoneyGoal]
    public let reservedCents: Int
    public let overReserved: Bool
    public let month: MonthSummary?
    public let monthly: [MonthSummary]
    public let places: [PlaceTotal]
    public let feed: [FeedItem]
    public let lastActivity: String?
    /// Days since the last operation when that is suspiciously long; null
    /// when the data is fresh.
    public let staleDays: Int?
    public let foreignCurrencies: [String]
    public let hashes: [String]

    public init(
        userId: String, displayName: String, hasAccounts: Bool, balanceCents: Int,
        balanceAsOf: String?, freeCents: Int, goals: [MoneyGoal], reservedCents: Int = 0,
        overReserved: Bool = false, month: MonthSummary? = nil, monthly: [MonthSummary] = [],
        places: [PlaceTotal] = [], feed: [FeedItem] = [], lastActivity: String? = nil,
        staleDays: Int? = nil, foreignCurrencies: [String] = [], hashes: [String] = []
    ) {
        self.userId = userId
        self.displayName = displayName
        self.hasAccounts = hasAccounts
        self.balanceCents = balanceCents
        self.balanceAsOf = balanceAsOf
        self.freeCents = freeCents
        self.goals = goals
        self.reservedCents = reservedCents
        self.overReserved = overReserved
        self.month = month
        self.monthly = monthly
        self.places = places
        self.feed = feed
        self.lastActivity = lastActivity
        self.staleDays = staleDays
        self.foreignCurrencies = foreignCurrencies
        self.hashes = hashes
    }

    private enum CodingKeys: String, CodingKey {
        case userId, displayName, hasAccounts, balanceCents, balanceAsOf, freeCents, goals
        case reservedCents, overReserved, month, monthly, places, feed, lastActivity, staleDays
        case foreignCurrencies, hashes
    }

    /// The fields the foundation build did not read are optional here: a
    /// response it cached before this build was installed must still show.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            userId: try c.decode(String.self, forKey: .userId),
            displayName: try c.decode(String.self, forKey: .displayName),
            hasAccounts: try c.decode(Bool.self, forKey: .hasAccounts),
            balanceCents: try c.decode(Int.self, forKey: .balanceCents),
            balanceAsOf: try c.decodeIfPresent(String.self, forKey: .balanceAsOf),
            freeCents: try c.decode(Int.self, forKey: .freeCents),
            goals: try c.decode([MoneyGoal].self, forKey: .goals),
            reservedCents: try c.decodeIfPresent(Int.self, forKey: .reservedCents) ?? 0,
            overReserved: try c.decodeIfPresent(Bool.self, forKey: .overReserved) ?? false,
            month: try c.decodeIfPresent(MonthSummary.self, forKey: .month),
            monthly: try c.decodeIfPresent([MonthSummary].self, forKey: .monthly) ?? [],
            places: try c.decodeIfPresent([PlaceTotal].self, forKey: .places) ?? [],
            feed: try c.decodeIfPresent([FeedItem].self, forKey: .feed) ?? [],
            lastActivity: try c.decodeIfPresent(String.self, forKey: .lastActivity),
            staleDays: try c.decodeIfPresent(Int.self, forKey: .staleDays),
            foreignCurrencies: try c.decodeIfPresent([String].self, forKey: .foreignCurrencies) ?? [],
            hashes: try c.decodeIfPresent([String].self, forKey: .hashes) ?? []
        )
    }

    public var id: String { userId }
}

/// A child sees their own money; a parent sees every child and the bank
/// accounts not yet given to anyone. The server says which by `role`; any
/// other role is a contract break and fails to decode.
public enum MoneyOverview: Decodable, Sendable, Equatable {
    case kid(me: MoneyMember, kid: KidMoney)
    case parent(me: MoneyMember, kids: [KidMoney], unassigned: [UnassignedAccount])

    private enum CodingKeys: String, CodingKey { case role, me, kid, kids, unassigned }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let me = try c.decode(MoneyMember.self, forKey: .me)
        switch try c.decode(String.self, forKey: .role) {
        case "kid":
            self = .kid(me: me, kid: try c.decode(KidMoney.self, forKey: .kid))
        case "parent":
            self = .parent(
                me: me,
                kids: try c.decode([KidMoney].self, forKey: .kids),
                unassigned: try c.decodeIfPresent([UnassignedAccount].self, forKey: .unassigned) ?? []
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .role, in: c, debugDescription: "unknown money role"
            )
        }
    }
}
