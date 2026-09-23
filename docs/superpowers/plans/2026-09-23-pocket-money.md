# Pocket money — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The native Money section does everything the web pocket-money page does, for a child and for a parent.

**Architecture:** Pure logic and tolerant models in `Sources/Core` (tested with `swift test`); the seven money actions in `AppAPI`; SwiftUI screens in `Sources/App/Money/`. No server changes.

**Tech Stack:** Swift 6, SwiftUI (iOS 26), Swift Charts, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-23-pocket-money-design.md`

## Global Constraints

- `Sources/Core` imports Foundation only.
- New kid-view fields decode with `decodeIfPresent` and neutral defaults, so a response cached by the foundation build still reads.
- Public repository: no hostnames, personal names or device identifiers.
- Changes need the network; a failure is shown to the person; after a success the money resource refreshes.
- `CORETEST` = `swift test` at the repo root → all pass. `BUILD` = `xcodegen && xcodebuild -project Oyloo.xcodeproj -scheme Oyloo -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` → `** BUILD SUCCEEDED **` (signed builds are made on the home Mac).
- `main` ships to family phones overnight: merge only after the owner checks the build.

---

### Task 1: Extended money models

**Files:**
- Modify: `Sources/Core/AppModels.swift` (`KidMoney`, `MoneyOverview`; new `MonthSummary`, `PlaceTotal`, `FeedItem`, `UnassignedAccount`)
- Modify: `Sources/Core/TodaySummary.swift` (parent case binding)
- Test: `Tests/CoreTests/MoneyModelsTests.swift`

**Interfaces:**
- Produces: `KidMoney` gains `reservedCents`, `overReserved`, `month: MonthSummary?`, `monthly`, `places`, `feed`, `lastActivity`, `staleDays`, `foreignCurrencies`, `hashes`; `MoneyOverview.parent(me:kids:unassigned:)`.

- [ ] **Step 1: Failing test**

```swift
import Foundation
import Testing
@testable import OylooCore

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try AppJSON.decoder.decode(type, from: Data(json.utf8))
}

@Suite struct MoneyModelsTests {
    @Test func fullKidViewDecodes() throws {
        let json = #"""
        {"userId":"k1","displayName":"Kid","hasAccounts":true,"hashes":["h1"],
         "balanceCents":2550,"balanceAsOf":"2026-09-22","reservedCents":1000,"freeCents":1550,
         "overReserved":false,"goals":[],
         "month":{"month":"2026-09","receivedCents":2000,"spentCents":450},
         "monthly":[{"month":"2026-08","receivedCents":1000,"spentCents":300}],
         "places":[{"name":"Shop","cents":450,"count":3}],
         "feed":[{"date":"2026-09-20","label":"Shop","amountCents":-150,"kind":"out"}],
         "lastActivity":"2026-09-20","staleDays":null,"foreignCurrencies":[]}
        """#
        let kid = try decode(KidMoney.self, json)
        #expect(kid.reservedCents == 1000)
        #expect(kid.month == MonthSummary(month: "2026-09", receivedCents: 2000, spentCents: 450))
        #expect(kid.monthly.count == 1)
        #expect(kid.places.first == PlaceTotal(name: "Shop", cents: 450, count: 3))
        #expect(kid.feed.first?.kind == "out")
        #expect(kid.hashes == ["h1"])
        #expect(kid.staleDays == nil)
    }

    @Test func minimalKidViewFromOlderCacheStillDecodes() throws {
        let json = #"""
        {"userId":"k1","displayName":"Kid","hasAccounts":false,"balanceCents":0,
         "balanceAsOf":null,"freeCents":0,"goals":[]}
        """#
        let kid = try decode(KidMoney.self, json)
        #expect(kid.reservedCents == 0 && !kid.overReserved)
        #expect(kid.month == nil && kid.monthly.isEmpty && kid.places.isEmpty && kid.feed.isEmpty)
        #expect(kid.foreignCurrencies.isEmpty && kid.hashes.isEmpty)
    }

    @Test func parentCarriesUnassignedAccounts() throws {
        let json = #"""
        {"role":"parent","me":{"userId":"p","role":"parent","displayName":"P"},"kids":[],
         "unassigned":[{"identificationHash":"h9","name":"Card","currency":"EUR","product":null,
                        "txCount":4,"lastActivity":"2026-09-01"}]}
        """#
        let money = try decode(MoneyOverview.self, json)
        guard case let .parent(_, _, unassigned) = money else { Issue.record("expected parent"); return }
        #expect(unassigned == [UnassignedAccount(identificationHash: "h9", name: "Card", currency: "EUR",
                                                 product: nil, txCount: 4, lastActivity: "2026-09-01")])
    }

    @Test func parentWithoutUnassignedFieldDecodesEmpty() throws {
        let json = #"{"role":"parent","me":{"userId":"p","role":"parent","displayName":"P"},"kids":[]}"#
        guard case let .parent(_, _, unassigned) = try decode(MoneyOverview.self, json) else {
            Issue.record("expected parent"); return
        }
        #expect(unassigned.isEmpty)
    }
}
```

Run: `CORETEST` → FAIL (`MonthSummary` not found).

- [ ] **Step 2: Implementation**

In `AppModels.swift`, replace `KidMoney` and `MoneyOverview` with:

```swift
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
```

In `TodaySummary.swift`: `case let .parent(_, kids):` → `case let .parent(_, kids, _):`.
In `Tests/CoreTests/AppModelsTests.swift` and `TodaySummaryTests.swift`: every `.parent(_, kids)` pattern → `.parent(_, kids, _)`; every `.parent(me: member, kids: [...])` construction → add `, unassigned: []`.

- [ ] **Step 3: Pass and commit**

Run: `CORETEST` → PASS.

```bash
git add Sources/Core Tests/CoreTests
git commit -m "feat(core): full pocket-money view with tolerant decoding"
```

---

### Task 2: Pure money logic

**Files:**
- Create: `Sources/Core/MoneyLogic.swift`
- Test: `Tests/CoreTests/MoneyLogicTests.swift`

**Interfaces:**
- Produces: `parseEuroInput(_:) -> Int?`; `MoneyWarning` (`.noAccounts`, `.stale(days:since:)`, `.overReserved`, `.foreignCurrency([String])`); `moneyWarnings(for:) -> [MoneyWarning]`; `GoalGroups { active; archived }`, `goalGroups(_:)`; `SpendPoint { kid; month; cents }`, `spendSeries(_ kids:, months:) -> [SpendPoint]`; `MoneyErrorCode` (raw-value enum of the server's codes).

- [ ] **Step 1: Failing test**

```swift
import Testing
@testable import OylooCore

private func goal(_ id: Int, archived: Bool = false, achieved: Bool = false) -> MoneyGoal {
    MoneyGoal(id: id, title: "g\(id)", targetCents: 100, savedCents: 0, percent: 0,
              achieved: achieved, archived: archived)
}

@Suite struct MoneyLogicTests {
    @Test func euroInputFollowsTheWebRule() {
        #expect(parseEuroInput("12") == 1200)
        #expect(parseEuroInput("12,5") == 1250)
        #expect(parseEuroInput("12.05") == 1205)
        #expect(parseEuroInput(" 1 250,00 ") == 125000)
        #expect(parseEuroInput("0") == 0)
        #expect(parseEuroInput("") == nil)
        #expect(parseEuroInput("12,345") == nil)
        #expect(parseEuroInput("-5") == nil)
        #expect(parseEuroInput("abc") == nil)
        #expect(parseEuroInput("1e3") == nil)
    }

    @Test func noAccountsHidesEveryOtherWarning() {
        let kid = KidMoney(userId: "k", displayName: "K", hasAccounts: false, balanceCents: 0,
                           balanceAsOf: nil, freeCents: 0, goals: [], overReserved: true,
                           staleDays: 30, foreignCurrencies: ["USD"])
        #expect(moneyWarnings(for: kid) == [.noAccounts])
    }

    @Test func warningsInPageOrder() {
        let kid = KidMoney(userId: "k", displayName: "K", hasAccounts: true, balanceCents: 0,
                           balanceAsOf: nil, freeCents: 0, goals: [], overReserved: true,
                           lastActivity: "2026-09-01", staleDays: 22, foreignCurrencies: ["USD"])
        #expect(moneyWarnings(for: kid) == [
            .stale(days: 22, since: "2026-09-01"), .foreignCurrency(["USD"]), .overReserved
        ])
    }

    @Test func staleNeedsBothDaysAndDate() {
        let kid = KidMoney(userId: "k", displayName: "K", hasAccounts: true, balanceCents: 0,
                           balanceAsOf: nil, freeCents: 0, goals: [], staleDays: 22)
        #expect(moneyWarnings(for: kid).isEmpty)
    }

    @Test func goalsSplitIntoActiveAndArchived() {
        let groups = goalGroups([goal(1), goal(2, archived: true), goal(3, achieved: true)])
        #expect(groups.active.map(\.id) == [1, 3])
        #expect(groups.archived.map(\.id) == [2])
    }

    @Test func spendSeriesTakesTheLastMonthsAcrossKids() {
        let a = KidMoney(userId: "a", displayName: "A", hasAccounts: true, balanceCents: 0,
                         balanceAsOf: nil, freeCents: 0, goals: [], monthly: [
                            MonthSummary(month: "2026-07", receivedCents: 0, spentCents: 10),
                            MonthSummary(month: "2026-08", receivedCents: 0, spentCents: 20),
                            MonthSummary(month: "2026-09", receivedCents: 0, spentCents: 30)])
        let b = KidMoney(userId: "b", displayName: "B", hasAccounts: true, balanceCents: 0,
                         balanceAsOf: nil, freeCents: 0, goals: [], monthly: [
                            MonthSummary(month: "2026-09", receivedCents: 0, spentCents: 5)])
        let series = spendSeries([a, b], months: 2)
        #expect(series == [
            SpendPoint(kid: "A", month: "2026-08", cents: 20),
            SpendPoint(kid: "A", month: "2026-09", cents: 30),
            SpendPoint(kid: "B", month: "2026-08", cents: 0),
            SpendPoint(kid: "B", month: "2026-09", cents: 5)
        ])
    }

    @Test func knownErrorCodesAreRecognised() {
        #expect(MoneyErrorCode(rawValue: "goal_title_too_long") == .goalTitleTooLong)
        #expect(MoneyErrorCode(rawValue: "password_too_short") == .passwordTooShort)
        #expect(MoneyErrorCode(rawValue: "something_new") == nil)
    }
}
```

Run: `CORETEST` → FAIL.

- [ ] **Step 2: Implementation**

```swift
import Foundation

/// The web page's rule for typed euro amounts: digits, optionally a dot or
/// comma and one or two decimals, spaces ignored. Returns cents.
public func parseEuroInput(_ raw: String) -> Int? {
    let trimmed = raw.filter { !$0.isWhitespace }
    guard !trimmed.isEmpty else { return nil }
    let parts = trimmed.split(separator: trimmed.contains(",") ? "," : ".", omittingEmptySubsequences: false)
    guard parts.count <= 2,
          let whole = parts.first, !whole.isEmpty, whole.allSatisfy(\.isASCII), whole.allSatisfy(\.isNumber),
          let wholeValue = Int(whole)
    else { return nil }
    var cents = 0
    if parts.count == 2 {
        let frac = parts[1]
        guard (1...2).contains(frac.count), frac.allSatisfy(\.isASCII), frac.allSatisfy(\.isNumber),
              let value = Int(frac.padding(toLength: 2, withPad: "0", startingAt: 0))
        else { return nil }
        cents = value
    }
    let (total, overflow) = wholeValue.multipliedReportingOverflow(by: 100)
    guard !overflow else { return nil }
    return total + cents
}

public enum MoneyWarning: Sendable, Equatable {
    case noAccounts
    case stale(days: Int, since: String)
    case foreignCurrency([String])
    case overReserved
}

/// In the order the web page shows them. Without an account there are no
/// numbers at all, so no other warning applies.
public func moneyWarnings(for kid: KidMoney) -> [MoneyWarning] {
    guard kid.hasAccounts else { return [.noAccounts] }
    var out: [MoneyWarning] = []
    if let days = kid.staleDays, let since = kid.lastActivity {
        out.append(.stale(days: days, since: since))
    }
    if !kid.foreignCurrencies.isEmpty { out.append(.foreignCurrency(kid.foreignCurrencies)) }
    if kid.overReserved { out.append(.overReserved) }
    return out
}

public struct GoalGroups: Sendable, Equatable {
    public let active: [MoneyGoal]
    public let archived: [MoneyGoal]
}

public func goalGroups(_ goals: [MoneyGoal]) -> GoalGroups {
    GoalGroups(active: goals.filter { !$0.archived }, archived: goals.filter(\.archived))
}

public struct SpendPoint: Sendable, Hashable {
    public let kid: String
    public let month: String
    public let cents: Int

    public init(kid: String, month: String, cents: Int) {
        self.kid = kid
        self.month = month
        self.cents = cents
    }
}

/// Spending per child for the last `months` months any child has data for,
/// zero where a child has none, children in the given order.
public func spendSeries(_ kids: [KidMoney], months: Int) -> [SpendPoint] {
    let allMonths = Set(kids.flatMap { $0.monthly.map(\.month) }).sorted().suffix(months)
    return kids.flatMap { kid in
        let byMonth = Dictionary(kid.monthly.map { ($0.month, $0.spentCents) }, uniquingKeysWith: { a, _ in a })
        return allMonths.map { SpendPoint(kid: kid.displayName, month: $0, cents: byMonth[$0] ?? 0) }
    }
}

/// Codes the server answers with; the app words the known ones itself.
public enum MoneyErrorCode: String, Sendable {
    case forbidden
    case goalTitleRequired = "goal_title_required"
    case goalTitleTooLong = "goal_title_too_long"
    case goalTargetInvalid = "goal_target_invalid"
    case goalUnknown = "goal_unknown"
    case amountInvalid = "amount_invalid"
    case depositRejected = "deposit_rejected"
    case emailInvalid = "email_invalid"
    case passwordTooShort = "password_too_short"
    case displayNameRequired = "display_name_required"
    case kidUnknown = "kid_unknown"
    case noAccountsSelected = "no_accounts_selected"
    case badRequest = "bad_request"
    case createUserFailed = "create_user_failed"
}
```

- [ ] **Step 3: Pass and commit**

Run: `CORETEST` → PASS.

```bash
git add Sources/Core/MoneyLogic.swift Tests/CoreTests/MoneyLogicTests.swift
git commit -m "feat(core): euro input, warnings, goal groups and spending series"
```

---

### Task 3: Money actions in the API client

**Files:**
- Modify: `Sources/Shared/AppAPI.swift`

**Interfaces:**
- Produces: `AppAPI.Failure.server(code: String, message: String)`; `createGoal(title:targetCents:)`, `moveMoney(goalId:amountCents:out:)`, `archiveGoal(id:)`, `unarchiveGoal(id:)`, `addKid(email:password:displayName:accountHashes:)`, `linkAccounts(userId:hashes:)`, `unlinkAccount(userId:hash:)` — all `async throws`.

- [ ] **Step 1: Implementation**

Add the case to `Failure` and its description:

```swift
        case server(code: String, message: String)
```

```swift
            case .server(_, let message): message
```

Add below `completeTask`:

```swift
    public static func createGoal(title: String, targetCents: Int) async throws {
        try await send("POST", "money/goals", ["title": title, "targetCents": targetCents])
    }

    public static func moveMoney(goalId: Int, amountCents: Int, out: Bool) async throws {
        try await send("POST", "money/goals/\(goalId)/moves",
                       ["amountCents": amountCents, "direction": out ? "out" : "in"])
    }

    public static func archiveGoal(id: Int) async throws {
        try await send("POST", "money/goals/\(id)/archive", [:])
    }

    public static func unarchiveGoal(id: Int) async throws {
        try await send("POST", "money/goals/\(id)/unarchive", [:])
    }

    public static func addKid(
        email: String, password: String, displayName: String, accountHashes: [String]
    ) async throws {
        try await send("POST", "money/kids", [
            "email": email, "password": password, "displayName": displayName,
            "accountHashes": accountHashes
        ])
    }

    public static func linkAccounts(userId: String, hashes: [String]) async throws {
        try await send("POST", "money/kids/\(pathSegment(userId))/accounts", ["hashes": hashes])
    }

    public static func unlinkAccount(userId: String, hash: String) async throws {
        try await send("DELETE", "money/kids/\(pathSegment(userId))/accounts/\(pathSegment(hash))", nil)
    }

    private static func pathSegment(_ raw: String) -> String {
        raw.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? raw
    }

    /// Writes answer `{ error, message }` on refusal; the code lets the
    /// screen word it, the message is the fallback.
    private static func send(_ method: String, _ path: String, _ body: [String: Any]?) async throws {
        var request = try await request(path: path)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? String {
                throw Failure.server(code: error, message: (json["message"] as? String) ?? error)
            }
            throw Failure.http(code)
        }
    }
```

- [ ] **Step 2: Build and commit**

Run: `BUILD`.

```bash
git add Sources/Shared/AppAPI.swift
git commit -m "feat(app): pocket-money actions in the API client"
```

---

### Task 4: Money screens

**Files:**
- Delete: `Sources/App/MoneyView.swift`
- Create: `Sources/App/Money/MoneyView.swift`, `KidMoneyScreen.swift`, `MoneySheets.swift`, `ParentMoneyScreen.swift`, `MoneyWords.swift`

**Interfaces:**
- Consumes: Tasks 1–3, `FamilyData`, `euros`, `FreshnessLabel`.
- Produces: `MoneyView(data:)` (same signature as before).

- [ ] **Step 1: Words for codes and warnings**

`Sources/App/Money/MoneyWords.swift`:

```swift
import Foundation

/// The person-facing text for a failed money action: known server codes in
/// the app's own words, anything else as the server phrased it.
func moneyFailureText(_ error: Error) -> String {
    if case let AppAPI.Failure.server(code, message) = error {
        switch MoneyErrorCode(rawValue: code) {
        case .goalTitleRequired: return String(localized: "Give the goal a name.")
        case .goalTitleTooLong: return String(localized: "The name is too long: 60 characters at most.")
        case .goalTargetInvalid: return String(localized: "Enter how much the goal needs.")
        case .amountInvalid: return String(localized: "Enter an amount above zero.")
        case .depositRejected: return String(localized: "Nothing moved: there is not that much in the goal.")
        case .emailInvalid: return String(localized: "That e-mail does not look right.")
        case .passwordTooShort: return String(localized: "The password needs at least 8 characters.")
        case .displayNameRequired: return String(localized: "Enter the child's name.")
        case .noAccountsSelected: return String(localized: "Pick at least one account.")
        case .forbidden: return String(localized: "This account has no access here.")
        case .createUserFailed: return String(localized: "The account was not created: \(message)")
        case .goalUnknown, .kidUnknown, .badRequest, .none: return message
        }
    }
    return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
}

func warningText(_ warning: MoneyWarning) -> String {
    switch warning {
    case .noAccounts:
        String(localized: "No bank account is linked to this account yet, so there are no numbers here — zeros would look like a real balance. Ask a parent to link one.")
    case let .stale(days, since):
        String(localized: "No data since \(since) — \(days) days. Either nothing happened on the account, or the bank sync has stopped.")
    case let .foreignCurrency(codes):
        String(localized: "A non-euro currency is linked (\(codes.joined(separator: ", "))). Everything is added up as euros, so the sums above cannot be trusted.")
    case .overReserved:
        String(localized: "More is set aside for goals than the account holds. The bank does not reserve it — the goals are only on paper, so some of them are not covered yet.")
    }
}
```

- [ ] **Step 2: Child screen and sheets**

`Sources/App/Money/KidMoneyScreen.swift`:

```swift
import SwiftUI

/// One child's money. Editable for the child themself; read-only when a
/// parent opens it, because the server only lets a child change their goals.
struct KidMoneyScreen: View {
    let kid: KidMoney
    let editable: Bool
    let data: FamilyData

    @State private var sheet: MoneySheet?
    @State private var showArchived = false
    @State private var failure: String?

    var body: some View {
        List {
            if let failure {
                Text(failure).foregroundStyle(.red).font(.footnote)
            }
            ForEach(Array(moneyWarnings(for: kid).enumerated()), id: \.offset) { _, warning in
                Label(warningText(warning), systemImage: "exclamationmark.triangle")
                    .font(.footnote)
            }
            if kid.hasAccounts {
                header
                goals
                places
                feed
            }
            FreshnessLabel(fetchedAt: data.money.fetchedAt, error: data.money.error)
        }
        .navigationTitle(kid.displayName)
        .refreshable { await data.money.refresh() }
        .sheet(item: $sheet) { sheet in
            sheet.view { action in await run(action) }
        }
    }

    private var header: some View {
        Section {
            LabeledContent("Balance") {
                VStack(alignment: .trailing) {
                    Text(euros(kid.balanceCents)).font(.title2.bold()).monospacedDigit()
                    if let asOf = kid.balanceAsOf {
                        Text("per the bank on \(asOf)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            LabeledContent("Free") { Text(euros(kid.freeCents)).monospacedDigit() }
            LabeledContent("Set aside for goals") { Text(euros(kid.reservedCents)).monospacedDigit() }
            if let month = kid.month {
                LabeledContent("Received this month") {
                    Text("+\(euros(month.receivedCents))").monospacedDigit().foregroundStyle(.green)
                }
                LabeledContent("Spent this month") {
                    Text("−\(euros(month.spentCents))").monospacedDigit()
                }
            }
        }
    }

    private var goals: some View {
        let groups = goalGroups(kid.goals)
        return Section {
            if groups.active.isEmpty {
                Text("No goals yet. What are you saving for?").foregroundStyle(.secondary)
            }
            ForEach(groups.active) { goal in goalRow(goal) }
            if editable {
                Button { sheet = .newGoal } label: { Label("New goal", systemImage: "plus") }
            }
            if !groups.archived.isEmpty {
                DisclosureGroup(isExpanded: $showArchived) {
                    ForEach(groups.archived) { goal in goalRow(goal) }
                } label: {
                    Text("Archive (\(groups.archived.count))")
                }
            }
        } header: {
            Text("Goals")
        }
    }

    private func goalRow(_ goal: MoneyGoal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(goal.title)
                if goal.achieved { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) }
                Spacer()
                Text("\(euros(goal.savedCents)) / \(euros(goal.targetCents))").monospacedDigit().font(.callout)
            }
            ProgressView(value: Double(min(goal.savedCents, goal.targetCents)), total: Double(max(goal.targetCents, 1)))
            if editable {
                HStack {
                    if goal.archived {
                        Button("Restore") { Task { await run { try await AppAPI.unarchiveGoal(id: goal.id) } } }
                    } else {
                        Button("Put in") { sheet = .move(goal, out: false) }
                        Button("Take out") { sheet = .move(goal, out: true) }
                        Spacer()
                        Button("Archive", role: .destructive) {
                            Task { await run { try await AppAPI.archiveGoal(id: goal.id) } }
                        }
                    }
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var places: some View {
        if !kid.places.isEmpty {
            Section("Where the money goes") {
                ForEach(kid.places, id: \.name) { place in
                    LabeledContent(place.name) {
                        Text("\(euros(place.cents)) · \(place.count)").monospacedDigit()
                    }
                }
            }
        }
    }

    @ViewBuilder private var feed: some View {
        if !kid.feed.isEmpty {
            Section("Recent operations") {
                ForEach(Array(kid.feed.enumerated()), id: \.offset) { _, item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.label).lineLimit(1)
                            Text(item.date).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(euros(item.amountCents)).monospacedDigit()
                            .foregroundStyle(item.kind == "in" ? .green : .primary)
                    }
                }
            }
        }
    }

    /// Online only: a refusal is shown here and nothing else changes.
    private func run(_ action: @escaping () async throws -> Void) async -> String? {
        do {
            try await action()
            failure = nil
            await data.money.refresh()
            return nil
        } catch {
            let text = moneyFailureText(error)
            failure = text
            return text
        }
    }
}
```

`Sources/App/Money/MoneySheets.swift`:

```swift
import SwiftUI

/// Sheets that collect an amount or a new goal. Each hands its action back
/// to the screen, which runs it and says whether it failed; the sheet
/// closes only on success so the typed values are not lost.
enum MoneySheet: Identifiable {
    case newGoal
    case move(MoneyGoal, out: Bool)

    var id: String {
        switch self {
        case .newGoal: "new"
        case let .move(goal, out): "move-\(goal.id)-\(out)"
        }
    }

    @MainActor @ViewBuilder
    func view(run: @escaping (@escaping () async throws -> Void) async -> String?) -> some View {
        switch self {
        case .newGoal: NewGoalSheet(run: run)
        case let .move(goal, out): MoveSheet(goal: goal, out: out, run: run)
        }
    }
}

struct NewGoalSheet: View {
    let run: (@escaping () async throws -> Void) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var target = ""
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("What are you saving for", text: $title)
                TextField("How much is needed, €", text: $target).keyboardType(.decimalPad)
                if let failure { Text(failure).foregroundStyle(.red) }
            }
            .navigationTitle(Text("New goal"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let name = title
                        let cents = parseEuroInput(target) ?? 0
                        Task {
                            failure = await run { try await AppAPI.createGoal(title: name, targetCents: cents) }
                            if failure == nil { dismiss() }
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct MoveSheet: View {
    let goal: MoneyGoal
    let out: Bool
    let run: (@escaping () async throws -> Void) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(goal.title) {
                    TextField("Amount, €", text: $amount).keyboardType(.decimalPad)
                }
                if let failure { Text(failure).foregroundStyle(.red) }
            }
            .navigationTitle(out ? Text("Take out") : Text("Put in"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let cents = parseEuroInput(amount) ?? 0
                        let id = goal.id
                        let isOut = out
                        Task {
                            failure = await run { try await AppAPI.moveMoney(goalId: id, amountCents: cents, out: isOut) }
                            if failure == nil { dismiss() }
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
```

- [ ] **Step 3: Parent screen**

`Sources/App/Money/ParentMoneyScreen.swift`:

```swift
import Charts
import SwiftUI

struct ParentMoneyScreen: View {
    let kids: [KidMoney]
    let unassigned: [UnassignedAccount]
    let data: FamilyData

    @State private var addingKid = false

    var body: some View {
        List {
            Section("Children") {
                ForEach(kids) { kid in
                    NavigationLink {
                        KidMoneyScreen(kid: kid, editable: false, data: data)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(kid.displayName).font(.headline)
                                Spacer()
                                Text(euros(kid.balanceCents)).monospacedDigit()
                            }
                            HStack {
                                Text("Free \(euros(kid.freeCents))")
                                Spacer()
                                if let month = kid.month { Text("Spent \(euros(month.spentCents))") }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if kids.contains(where: { !$0.monthly.isEmpty }) {
                Section("Spending by month") {
                    Chart(spendSeries(kids, months: 6), id: \.self) { point in
                        BarMark(x: .value("Month", point.month), y: .value("€", Double(point.cents) / 100))
                            .foregroundStyle(by: .value("Child", point.kid))
                            .position(by: .value("Child", point.kid))
                    }
                    .frame(height: 200)
                }
            }
            Section("Admin") {
                ForEach(kids) { kid in
                    NavigationLink {
                        KidAccountsView(kid: kid, unassigned: unassigned, data: data)
                    } label: {
                        Label("\(kid.displayName): accounts", systemImage: "building.columns")
                    }
                }
                Button { addingKid = true } label: { Label("Add child", systemImage: "person.badge.plus") }
            }
            FreshnessLabel(fetchedAt: data.money.fetchedAt, error: data.money.error)
        }
        .refreshable { await data.money.refresh() }
        .sheet(isPresented: $addingKid) { AddKidSheet(unassigned: unassigned, data: data) }
    }
}

/// Linked accounts are shown by a short form of their bank hash: the server
/// sends names only for accounts nobody owns yet.
struct KidAccountsView: View {
    let kid: KidMoney
    let unassigned: [UnassignedAccount]
    let data: FamilyData
    @State private var failure: String?

    var body: some View {
        List {
            if let failure { Text(failure).foregroundStyle(.red).font(.footnote) }
            Section("Linked") {
                if kid.hashes.isEmpty { Text("No accounts linked").foregroundStyle(.secondary) }
                ForEach(kid.hashes, id: \.self) { hash in
                    Text("…" + hash.suffix(8)).monospaced()
                }
                .onDelete { offsets in
                    let hashes = offsets.map { kid.hashes[$0] }
                    Task {
                        for hash in hashes {
                            await act { try await AppAPI.unlinkAccount(userId: kid.userId, hash: hash) }
                        }
                    }
                }
            }
            Section("Not linked to anyone") {
                if unassigned.isEmpty { Text("None").foregroundStyle(.secondary) }
                ForEach(unassigned) { account in
                    Button {
                        Task { await act { try await AppAPI.linkAccounts(userId: kid.userId, hashes: [account.identificationHash]) } }
                    } label: {
                        accountLabel(account)
                    }
                }
            }
        }
        .navigationTitle(kid.displayName)
    }

    private func act(_ action: @escaping () async throws -> Void) async {
        do {
            try await action()
            failure = nil
            await data.money.refresh()
        } catch {
            failure = moneyFailureText(error)
        }
    }
}

func accountLabel(_ account: UnassignedAccount) -> some View {
    VStack(alignment: .leading) {
        Text(account.name ?? account.product ?? "…" + account.identificationHash.suffix(8))
        Text("\(account.currency ?? "?") · \(account.txCount) ops · \(account.lastActivity ?? "—")")
            .font(.caption2).foregroundStyle(.secondary)
    }
}

struct AddKidSheet: View {
    let unassigned: [UnassignedAccount]
    let data: FamilyData
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var picked: Set<String> = []
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("E-mail", text: $email)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password, at least 8 characters", text: $password)
                        .textContentType(.newPassword)
                }
                if !unassigned.isEmpty {
                    Section("Bank accounts") {
                        ForEach(unassigned) { account in
                            Button {
                                if picked.contains(account.id) { picked.remove(account.id) } else { picked.insert(account.id) }
                            } label: {
                                HStack {
                                    accountLabel(account)
                                    Spacer()
                                    if picked.contains(account.id) { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }
                }
                if let failure { Text(failure).foregroundStyle(.red) }
            }
            .navigationTitle(Text("Add child"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                }
            }
        }
    }

    private func create() async {
        do {
            try await AppAPI.addKid(email: email, password: password, displayName: name,
                                    accountHashes: Array(picked))
            await data.money.refresh()
            dismiss()
        } catch {
            failure = moneyFailureText(error)
        }
    }
}
```

`Sources/App/Money/MoneyView.swift`:

```swift
import SwiftUI

/// The Money section: the child's own screen, or the parent's overview.
struct MoneyView: View {
    let data: FamilyData

    var body: some View {
        NavigationStack {
            Group {
                switch data.money.value {
                case let .kid(_, kid):
                    KidMoneyScreen(kid: kid, editable: true, data: data)
                case let .parent(_, kids, unassigned):
                    ParentMoneyScreen(kids: kids, unassigned: unassigned, data: data)
                        .navigationTitle(Text("Money"))
                case .none:
                    List { FreshnessLabel(fetchedAt: data.money.fetchedAt, error: data.money.error) }
                        .navigationTitle(Text("Money"))
                        .refreshable { await data.money.refresh() }
                }
            }
        }
    }
}
```

- [ ] **Step 4: Build and commit**

Run: `git rm Sources/App/MoneyView.swift` then `BUILD`. Fix compile errors only in files of this task.

```bash
git add Sources/App
git commit -m "feat(app): pocket-money screens for a child and a parent"
```

---

### Task 5: Strings

**Files:**
- Modify: `Sources/App/Localizable.xcstrings`

- [ ] **Step 1:** Build once so Xcode adds the new keys to the catalog as `new` (or list them from Tasks 4's `String(localized:)`, `Text`, `Label`, `Button`, `Section`, `LabeledContent`, `TextField`, `SecureField` literals). Give every one a Russian and a Latvian translation, keeping the web page's wording for the warnings and the goal texts. Interpolations use the catalog's specifiers (`%@`, `%lld`).
- [ ] **Step 2:** `BUILD`; check `ru.lproj` and `lv.lproj` contain the new keys (`plutil -p "$APP/ru.lproj/Localizable.strings" | grep -c .`).
- [ ] **Step 3:** Commit: `feat(app): Russian and Latvian for pocket money`.

---

### Task 6: Device check and merge

- [ ] **Step 1:** `CORETEST` and `BUILD` green on the final tree rebased on `origin/main`.
- [ ] **Step 2:** Signed build on the home Mac (temporary launchd job in the GUI session, as for the foundation); install on the owner's phone by cable or Wi-Fi; console shows no decode errors.
- [ ] **Step 3:** Owner checks as a parent: children list, chart, a child's read-only screen, accounts screen, Add child form (may cancel without creating).
- [ ] **Step 4:** Only then push to `main` with a per-command token for `ed-ilyin`, verifying the login in the same command.

---

## Self-review

- **Spec coverage:** child header, warnings, goals with put in/take out/archive/restore/new, places, feed — Task 4 `KidMoneyScreen` and sheets; parent children list, read-only child screen, six-month chart, add child, link/unlink — Task 4 `ParentMoneyScreen`, `KidAccountsView`, `AddKidSheet`; tolerant decoding — Task 1; euro rule, warnings order, goal groups, series, error codes — Task 2; seven actions and error body — Task 3; three languages — Task 5; owner check before `main` — Task 6.
- **No placeholders:** Task 5 names its keys by reference to Task 4's literals, which are all in this plan.
- **Names:** `MonthSummary`, `PlaceTotal`, `FeedItem`, `UnassignedAccount`, `MoneyOverview.parent(me:kids:unassigned:)`, `parseEuroInput`, `MoneyWarning`, `moneyWarnings(for:)`, `goalGroups`, `spendSeries`, `SpendPoint`, `MoneyErrorCode`, `AppAPI.Failure.server`, `moneyFailureText`, `warningText`, `MoneySheet`, `KidMoneyScreen`, `ParentMoneyScreen`, `KidAccountsView`, `AddKidSheet`, `accountLabel` are consistent.
