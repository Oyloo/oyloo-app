# App foundation — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A signed-in family member lands on a Today screen built from their own data, with the sections the server allows one tap away, readable offline.

**Architecture:** Pure Foundation logic in `Sources/Core` (models, cache, section visibility, Today assembly, freshness) tested with `swift test` via a root `Package.swift`; networking glue in `Sources/Shared` (`AppAPI`, `CachedResource`); SwiftUI screens in `Sources/App` (`RootView`, `TodayView`, `TasksView`, `MoneyView`, the existing capture UI embedded as a section).

**Tech Stack:** Swift 6, SwiftUI (iOS 26), Observation, Swift Testing, xcodegen.

**Spec:** `docs/superpowers/specs/2026-09-23-app-foundation-design.md`

## Global Constraints

- `Sources/Core` imports Foundation only — no UIKit, SwiftUI, Security or AuthenticationServices — so `swift test` runs on macOS.
- Decoders read only the fields in the spec's contract table; unknown fields are ignored.
- Public repository: no server hostnames, personal names, device identifiers or team-private detail in code, comments or strings.
- Device verification only; `main` ships to family phones overnight, so merge to `main` only after the build is checked on a device.
- Build check: `xcodegen && xcodebuild -project Oyloo.xcodeproj -scheme Oyloo -configuration Debug -destination 'generic/platform=iOS' -allowProvisioningUpdates build` → `** BUILD SUCCEEDED **` (below: `BUILD`).
- Core tests: `swift test` at the repository root → all pass (below: `CORETEST`).
- Commit messages end with the `Co-Authored-By` trailer the session uses.

---

### Task 1: Package and response models

**Files:**
- Create: `Package.swift`
- Create: `Sources/Core/AppModels.swift`
- Test: `Tests/CoreTests/AppModelsTests.swift`

**Interfaces:**
- Produces: `Me`, `TaskItem`, `TasksOverview`, `MoneyGoal`, `KidMoney`, `MoneyMember`, `MoneyOverview` (`.kid(me:kid:)`, `.parent(me:kids:)`), `AppJSON.decoder`.

- [ ] **Step 1: Package manifest**

```swift
// swift-tools-version: 6.0
// Describes only the pure core so its tests run on a Mac with `swift test`.
// The app itself is built from project.yml; it compiles Sources/Core
// directly, so there is no package dependency to resolve in Xcode.
import PackageDescription

let package = Package(
    name: "OylooCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "OylooCore", targets: ["OylooCore"])],
    targets: [
        .target(name: "OylooCore", path: "Sources/Core"),
        .testTarget(name: "CoreTests", dependencies: ["OylooCore"], path: "Tests/CoreTests")
    ]
)
```

- [ ] **Step 2: Failing test**

`Tests/CoreTests/AppModelsTests.swift`:

```swift
import Foundation
import Testing
@testable import OylooCore

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try AppJSON.decoder.decode(type, from: Data(json.utf8))
}

@Suite struct AppModelsTests {
    @Test func meDecodesAndIgnoresExtraFields() throws {
        let me = try decode(Me.self, #"{"userId":"u1","name":"Kid","sections":["money","tasks","captures"],"later":1}"#)
        #expect(me == Me(userId: "u1", name: "Kid", sections: ["money", "tasks", "captures"]))
    }

    @Test func meAllowsMissingName() throws {
        let me = try decode(Me.self, #"{"userId":"u1","name":null,"sections":[]}"#)
        #expect(me.name == nil)
    }

    @Test func tasksOverviewKeepsOrderAndFlags() throws {
        let json = #"""
        {"today":"2026-09-23","view":"today","tag":null,"counts":{"today":2,"done":1},
         "todos":[
          {"id":"t1","title":"Homework","status":"next","important":true,"due":"2026-09-23",
           "circleId":null,"priority":"P1","overdue":false,"urgent":true,"notes":null,"tags":["school"]},
          {"id":"t2","title":"Bins","status":"done","important":false,"due":null,
           "circleId":"family","priority":"P4","overdue":false,"urgent":false}
         ],"tags":[],"circles":[]}
        """#
        let overview = try decode(TasksOverview.self, json)
        #expect(overview.todos.map(\.id) == ["t1", "t2"])
        #expect(overview.todos[0].isOpen)
        #expect(!overview.todos[1].isOpen)
        #expect(overview.counts["today"] == 2)
    }

    @Test func moneyDecodesKidView() throws {
        let json = #"""
        {"role":"kid","me":{"userId":"k1","role":"kid","displayName":"Kid"},
         "kid":{"userId":"k1","displayName":"Kid","hasAccounts":true,"hashes":["h"],
          "balanceCents":2550,"balanceAsOf":"2026-09-22","freeCents":1550,"reservedCents":1000,
          "goals":[{"id":3,"title":"Bike","targetCents":15000,"savedCents":1000,"remainingCents":14000,
                    "percent":7,"achieved":false,"archived":false}],
          "feed":[],"places":[]}}
        """#
        let money = try decode(MoneyOverview.self, json)
        guard case let .kid(me, kid) = money else { Issue.record("expected kid"); return }
        #expect(me.displayName == "Kid")
        #expect(kid.balanceCents == 2550)
        #expect(kid.goals.first?.remainingCents == 14000)
    }

    @Test func moneyDecodesParentView() throws {
        let json = #"""
        {"role":"parent","me":{"userId":"p1","role":"parent","displayName":"Parent"},
         "kids":[{"userId":"k1","displayName":"A","hasAccounts":false,"balanceCents":0,
                  "balanceAsOf":null,"freeCents":0,"goals":[]}],
         "unassigned":[]}
        """#
        let money = try decode(MoneyOverview.self, json)
        guard case let .parent(_, kids) = money else { Issue.record("expected parent"); return }
        #expect(kids.map(\.displayName) == ["A"])
    }

    @Test func moneyRejectsUnknownRole() {
        #expect(throws: DecodingError.self) {
            try decode(MoneyOverview.self, #"{"role":"guest","me":{"userId":"x","role":"guest","displayName":"x"}}"#)
        }
    }
}
```

Run: `swift test` → FAIL (types not found).

- [ ] **Step 3: Implementation**

`Sources/Core/AppModels.swift`:

```swift
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
```

- [ ] **Step 4: Pass and commit**

Run: `CORETEST` → PASS.

```bash
git add Package.swift Sources/Core/AppModels.swift Tests/CoreTests/AppModelsTests.swift
git commit -m "feat(core): family API response models, tested with swift test"
```

---

### Task 2: Response cache

**Files:**
- Create: `Sources/Core/ResponseCache.swift`
- Test: `Tests/CoreTests/ResponseCacheTests.swift`

**Interfaces:**
- Produces: `ResponseCache(directory:)`, `ResponseCache.forServer(_ baseURL: String, root: URL)`, `store(_:for:at:)`, `load(_:) -> CachedBody?`, `clear()`; `CachedBody { data; fetchedAt }`.

- [ ] **Step 1: Failing test**

```swift
import Foundation
import Testing
@testable import OylooCore

@Suite struct ResponseCacheTests {
    private func tempCache() -> ResponseCache {
        ResponseCache(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("cache-\(UUID().uuidString)", isDirectory: true))
    }

    @Test func roundTripKeepsBodyAndTime() throws {
        let cache = tempCache()
        let when = Date(timeIntervalSince1970: 1_790_000_000)
        try cache.store(Data("{\"a\":1}".utf8), for: "tasks?view=today", at: when)
        let hit = try #require(cache.load("tasks?view=today"))
        #expect(hit.data == Data("{\"a\":1}".utf8))
        #expect(abs(hit.fetchedAt.timeIntervalSince(when)) < 1)
    }

    @Test func missReturnsNil() {
        #expect(tempCache().load("me") == nil)
    }

    @Test func storeReplacesPreviousBody() throws {
        let cache = tempCache()
        try cache.store(Data("1".utf8), for: "me")
        try cache.store(Data("2".utf8), for: "me")
        #expect(cache.load("me")?.data == Data("2".utf8))
    }

    @Test func keysWithSlashesAndQueriesStaySeparate() throws {
        let cache = tempCache()
        try cache.store(Data("a".utf8), for: "tasks?view=today")
        try cache.store(Data("b".utf8), for: "tasks?view=done")
        #expect(cache.load("tasks?view=today")?.data == Data("a".utf8))
        #expect(cache.load("tasks?view=done")?.data == Data("b".utf8))
    }

    @Test func clearRemovesEverything() throws {
        let cache = tempCache()
        try cache.store(Data("1".utf8), for: "me")
        cache.clear()
        #expect(cache.load("me") == nil)
    }

    @Test func serversGetSeparateFolders() {
        let root = FileManager.default.temporaryDirectory
        let a = ResponseCache.forServer("https://one.example/", root: root)
        let b = ResponseCache.forServer("https://two.example/", root: root)
        #expect(a.directory != b.directory)
    }
}
```

Run: `CORETEST` → FAIL.

- [ ] **Step 2: Implementation**

```swift
import Foundation

public struct CachedBody: Sendable, Equatable {
    public let data: Data
    public let fetchedAt: Date
}

/// Last successful response of each call, kept on disk so screens have
/// something to show without a network. One folder per server; the time
/// a body arrived is the file's modification date, set explicitly.
public struct ResponseCache: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Caches go under the system caches folder by default: the OS may purge
    /// them under storage pressure, which is fine — the next refresh refills.
    public static func forServer(
        _ baseURL: String,
        root: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    ) -> ResponseCache {
        ResponseCache(directory: root
            .appendingPathComponent("app-api", isDirectory: true)
            .appendingPathComponent(safeName(baseURL), isDirectory: true))
    }

    public func store(_ data: Data, for key: String, at date: Date = Date()) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(key)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    public func load(_ key: String) -> CachedBody? {
        let url = fileURL(key)
        guard let data = try? Data(contentsOf: url),
              let date = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        else { return nil }
        return CachedBody(data: data, fetchedAt: date)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func fileURL(_ key: String) -> URL {
        directory.appendingPathComponent(Self.safeName(key) + ".json")
    }

    /// Letters and digits kept, everything else becomes "_" plus a stable
    /// checksum, so "tasks?view=a/b" and "tasks?view=a_b" never collide.
    static func safeName(_ raw: String) -> String {
        let kept = String(raw.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? Character($0) : "_"
        })
        var hash: UInt64 = 1469598103934665603
        for byte in raw.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        return kept.prefix(80) + "-" + String(hash, radix: 16)
    }
}
```

- [ ] **Step 3: Pass and commit**

Run: `CORETEST` → PASS.

```bash
git add Sources/Core/ResponseCache.swift Tests/CoreTests/ResponseCacheTests.swift
git commit -m "feat(core): on-disk cache of the last response per call"
```

---

### Task 3: Sections, Today assembly, freshness

**Files:**
- Create: `Sources/Core/Sections.swift`, `Sources/Core/TodaySummary.swift`, `Sources/Core/Freshness.swift`
- Test: `Tests/CoreTests/SectionsTests.swift`, `Tests/CoreTests/TodaySummaryTests.swift`, `Tests/CoreTests/FreshnessTests.swift`

**Interfaces:**
- Produces: `AppSection` (`today, money, tasks, captures, settings`), `visibleSections(me: Me?) -> [AppSection]`; `TodaySummary.make(tasks:money:)` with `tasks`, `openTaskCount`, `money: [MoneyLine]`; `MoneyLine { name; balanceCents; nextGoal: MoneyGoal? }`; `latest(_:count:date:)`; `Freshness.of(_:now:)`.

- [ ] **Step 1: Failing tests**

`SectionsTests.swift`:

```swift
import Testing
@testable import OylooCore

@Suite struct SectionsTests {
    @Test func beforeFirstMeOnlyCapturesWork() {
        #expect(visibleSections(me: nil) == [.today, .captures, .settings])
    }

    @Test func serverListDecidesAndOrderIsFixed() {
        let me = Me(userId: "u", name: nil, sections: ["captures", "tasks", "money"])
        #expect(visibleSections(me: me) == [.today, .money, .tasks, .captures, .settings])
    }

    @Test func missingSectionIsHidden() {
        let me = Me(userId: "u", name: nil, sections: ["tasks", "captures"])
        #expect(!visibleSections(me: me).contains(.money))
    }

    @Test func unknownSectionNamesAreIgnored() {
        let me = Me(userId: "u", name: nil, sections: ["school", "tasks"])
        #expect(visibleSections(me: me) == [.today, .tasks, .settings])
    }
}
```

`TodaySummaryTests.swift`:

```swift
import Foundation
import Testing
@testable import OylooCore

private func task(_ id: String, _ status: String = "next") -> TaskItem {
    TaskItem(id: id, title: id, status: status, important: false, due: nil,
             circleId: nil, priority: "P4", overdue: false)
}

private func goal(_ id: Int, target: Int, saved: Int, achieved: Bool = false, archived: Bool = false) -> MoneyGoal {
    MoneyGoal(id: id, title: "g\(id)", targetCents: target, savedCents: saved,
              percent: 0, achieved: achieved, archived: archived)
}

private func kid(_ name: String, balance: Int, goals: [MoneyGoal]) -> KidMoney {
    KidMoney(userId: name, displayName: name, hasAccounts: true, balanceCents: balance,
             balanceAsOf: nil, freeCents: balance, goals: goals)
}

private let member = MoneyMember(userId: "m", role: "kid", displayName: "Me")

@Suite struct TodaySummaryTests {
    @Test func openTasksOnlyAtMostFiveInServerOrder() {
        let todos = [task("a"), task("b", "done"), task("c"), task("d"), task("e"),
                     task("f", "dropped"), task("g"), task("h")]
        let overview = TasksOverview(today: "2026-09-23", view: "today", counts: [:], todos: todos)
        let summary = TodaySummary.make(tasks: overview, money: nil)
        #expect(summary.tasks.map(\.id) == ["a", "c", "d", "e", "g"])
        #expect(summary.openTaskCount == 6)
    }

    @Test func kidSeesOwnBalanceAndNearestActiveGoal() {
        let goals = [goal(1, target: 1000, saved: 100), goal(2, target: 500, saved: 400),
                     goal(3, target: 100, saved: 100, achieved: true),
                     goal(4, target: 50, saved: 0, archived: true)]
        let summary = TodaySummary.make(tasks: nil, money: .kid(me: member, kid: kid("Me", balance: 700, goals: goals)))
        #expect(summary.money == [MoneyLine(name: "Me", balanceCents: 700, nextGoal: goals[1])])
    }

    @Test func parentSeesEveryKid() {
        let summary = TodaySummary.make(tasks: nil, money: .parent(me: member, kids: [
            kid("A", balance: 10, goals: []), kid("B", balance: 20, goals: [goal(9, target: 5, saved: 1)])
        ]))
        #expect(summary.money.map(\.name) == ["A", "B"])
        #expect(summary.money[0].nextGoal == nil)
        #expect(summary.money[1].nextGoal?.id == 9)
    }

    @Test func nothingLoadedIsEmpty() {
        let summary = TodaySummary.make(tasks: nil, money: nil)
        #expect(summary.tasks.isEmpty && summary.money.isEmpty && summary.openTaskCount == 0)
    }

    @Test func latestTakesNewestFirst() {
        struct Item: Equatable { let id: Int; let at: Date }
        let items = [Item(id: 1, at: Date(timeIntervalSince1970: 1)),
                     Item(id: 2, at: Date(timeIntervalSince1970: 3)),
                     Item(id: 3, at: Date(timeIntervalSince1970: 2))]
        #expect(latest(items, count: 2, date: \.at).map(\.id) == [2, 3])
    }
}
```

`FreshnessTests.swift`:

```swift
import Foundation
import Testing
@testable import OylooCore

@Suite struct FreshnessTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func buckets() {
        #expect(Freshness.of(now.addingTimeInterval(-30), now: now) == .justNow)
        #expect(Freshness.of(now.addingTimeInterval(-5 * 60), now: now) == .minutes(5))
        #expect(Freshness.of(now.addingTimeInterval(-3 * 3600), now: now) == .hours(3))
        #expect(Freshness.of(now.addingTimeInterval(-2 * 86400), now: now) == .days(2))
    }

    @Test func futureDatesCountAsJustNow() {
        #expect(Freshness.of(now.addingTimeInterval(120), now: now) == .justNow)
    }
}
```

Run: `CORETEST` → FAIL.

- [ ] **Step 2: Implementation**

`Sources/Core/Sections.swift`:

```swift
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
```

`Sources/Core/TodaySummary.swift`:

```swift
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
        case let .parent(_, kids):
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
```

`Sources/Core/Freshness.swift`:

```swift
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
```

- [ ] **Step 3: Pass and commit**

Run: `CORETEST` → PASS.

```bash
git add Sources/Core Tests/CoreTests
git commit -m "feat(core): section visibility, Today assembly and freshness"
```

---

### Task 4: Networking glue in the app

**Files:**
- Modify: `project.yml` (both targets compile `Sources/Core`)
- Create: `Sources/Shared/AppAPI.swift`
- Create: `Sources/Shared/CachedResource.swift`
- Modify: `Sources/Shared/OAuthClient.swift` (`signOut` clears the cache)

**Interfaces:**
- Consumes: Tasks 1–3; `OAuthClient.validAccessToken()`, `SyncSettings`.
- Produces: `AppAPI.me()`, `.tasks(view:)`, `.money()`, `.completeTask(id:)`, `AppAPI.cache`; `@MainActor @Observable CachedResource<Value: Decodable & Sendable>` with `value`, `fetchedAt`, `error`, `isLoading`, `refresh()`.

- [ ] **Step 1: Project**

In `project.yml`, add `- Sources/Core` to the `sources` of both `Oyloo` and `ShareExtension` (next to `- Sources/Shared`).

- [ ] **Step 2: API client**

`Sources/Shared/AppAPI.swift`:

```swift
import Foundation

/// The family app API: one place that knows paths, the bearer token and the
/// cache. Every successful GET also lands in the cache, so the next launch
/// shows it before the network answers.
public enum AppAPI {
    public enum Failure: LocalizedError {
        case notConfigured
        case notSignedIn
        case http(Int)

        public var errorDescription: String? {
            switch self {
            case .notConfigured: String(localized: "Set the server address in Settings.")
            case .notSignedIn: String(localized: "Sign in to see this.")
            case .http(401): String(localized: "The server refused the sign-in. Sign in again.")
            case .http(403): String(localized: "This account has no access here.")
            case .http(let code): String(localized: "The server answered \(code).")
            }
        }
    }

    public static var cache: ResponseCache { ResponseCache.forServer(SyncSettings.baseURL) }

    public static func me() async throws -> CachedBody { try await get("me") }
    public static func money() async throws -> CachedBody { try await get("money") }
    public static func tasks(view: String) async throws -> CachedBody {
        try await get("tasks", query: [URLQueryItem(name: "view", value: view)])
    }

    public static func completeTask(id: String) async throws {
        var request = try await request(path: "tasks/\(id)")
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["status": "done"])
        let (_, response) = try await URLSession.shared.data(for: request)
        try check(response)
    }

    /// Cache key for a call; the same string `CachedResource` reads back.
    public static func key(_ path: String, query: [URLQueryItem] = []) -> String {
        query.isEmpty ? path : path + "?" + query.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
    }

    private static func get(_ path: String, query: [URLQueryItem] = []) async throws -> CachedBody {
        var request = try await request(path: path, query: query)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response)
        let now = Date()
        try? cache.store(data, for: key(path, query: query), at: now)
        return CachedBody(data: data, fetchedAt: now)
    }

    private static func request(path: String, query: [URLQueryItem] = []) async throws -> URLRequest {
        guard SyncSettings.isConfigured, let base = URL(string: SyncSettings.baseURL) else {
            throw Failure.notConfigured
        }
        var components = URLComponents(
            url: base.appendingPathComponent("api/app/v1/" + path), resolvingAgainstBaseURL: false
        )
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw Failure.notConfigured }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        guard let token = try? await OAuthClient.validAccessToken() else { throw Failure.notSignedIn }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func check(_ response: URLResponse) throws {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw Failure.http(code) }
    }
}
```

- [ ] **Step 3: Observable resource**

`Sources/Shared/CachedResource.swift`:

```swift
import Foundation
import Observation

/// A value from the API that screens can show at once from the cache and
/// refresh from the network. A failed refresh keeps the cached value and
/// records why, so the screen can say both what it has and what went wrong.
@MainActor
@Observable
public final class CachedResource<Value: Decodable & Sendable> {
    public private(set) var value: Value?
    public private(set) var fetchedAt: Date?
    public private(set) var error: String?
    public private(set) var isLoading = false

    private let key: String
    private let fetch: @Sendable () async throws -> CachedBody

    public init(key: String, fetch: @escaping @Sendable () async throws -> CachedBody) {
        self.key = key
        self.fetch = fetch
        if let cached = AppAPI.cache.load(key), let decoded = Self.decode(cached.data) {
            value = decoded
            fetchedAt = cached.fetchedAt
        }
    }

    public func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let body = try await fetch()
            guard let decoded = Self.decode(body.data) else {
                error = String(localized: "The server sent something this version cannot read.")
                return
            }
            value = decoded
            fetchedAt = body.fetchedAt
            error = nil
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static func decode(_ data: Data) -> Value? {
        try? AppJSON.decoder.decode(Value.self, from: data)
    }
}
```

- [ ] **Step 4: Sign-out clears the cache**

In `OAuthClient.signOut()`, before `TokenStore.clear(for: base)`:

```swift
        // Personal devices, but the next account must never see the last
        // one's money or tasks, even for the moment before a refresh.
        ResponseCache.forServer(base).clear()
```

- [ ] **Step 5: Build and commit**

Run: `BUILD`.

```bash
git add project.yml Sources/Shared/AppAPI.swift Sources/Shared/CachedResource.swift Sources/Shared/OAuthClient.swift
git commit -m "feat(app): API client and cached resources for the family endpoints"
```

---

### Task 5: Screens

**Files:**
- Create: `Sources/App/RootView.swift`, `Sources/App/TodayView.swift`, `Sources/App/TasksView.swift`, `Sources/App/MoneyView.swift`, `Sources/App/FamilyData.swift`, `Sources/App/FreshnessLabel.swift`
- Modify: `Sources/App/OylooApp.swift` (root view), `Sources/App/ContentView.swift` (embedded mode)

**Interfaces:**
- Consumes: Tasks 1–4; `ContentView`, `VaultManagementView`, `CaptureFeed`.
- Produces: `FamilyData` (`@MainActor @Observable`, holds `me`, `tasksToday`, `money` resources and `captures: CaptureFeed`, `refreshAll()`).

- [ ] **Step 1: Shared data**

`Sources/App/FamilyData.swift`:

```swift
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
```

- [ ] **Step 2: Freshness label**

`Sources/App/FreshnessLabel.swift`:

```swift
import SwiftUI

/// "Updated 5 min ago" under a block; red with the reason when the last
/// refresh failed, so stale data is never mistaken for current.
struct FreshnessLabel: View {
    let fetchedAt: Date?
    let error: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 2) {
                if let fetchedAt {
                    Text(words(Freshness.of(fetchedAt, now: context.date)))
                        .foregroundStyle(.secondary)
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .font(.caption2)
        }
    }

    private func words(_ f: Freshness) -> String {
        switch f {
        case .justNow: String(localized: "Updated just now")
        case .minutes(let n): String(localized: "Updated \(n) min ago")
        case .hours(let n): String(localized: "Updated \(n) h ago")
        case .days(let n): String(localized: "Updated \(n) d ago")
        }
    }
}

func euros(_ cents: Int) -> String {
    (Double(cents) / 100).formatted(.currency(code: "EUR"))
}
```

- [ ] **Step 3: Today**

`Sources/App/TodayView.swift`:

```swift
import SwiftUI

struct TodayView: View {
    let data: FamilyData
    let open: (AppSection) -> Void

    private var summary: TodaySummary {
        TodaySummary.make(tasks: data.tasksToday.value, money: data.money.value)
    }

    var body: some View {
        NavigationStack {
            List {
                if data.sections.contains(.tasks) { tasksBlock }
                if data.sections.contains(.money) { moneyBlock }
                if data.sections.contains(.captures) { capturesBlock }
            }
            .navigationTitle(Text("Today"))
            .refreshable { await data.refreshAll() }
        }
    }

    private var tasksBlock: some View {
        Section {
            if summary.tasks.isEmpty {
                Text("Nothing due today").foregroundStyle(.secondary)
            }
            ForEach(summary.tasks) { task in
                Label(task.title, systemImage: task.overdue ? "exclamationmark.circle" : "circle")
            }
            if summary.openTaskCount > summary.tasks.count {
                Text("and \(summary.openTaskCount - summary.tasks.count) more").foregroundStyle(.secondary)
            }
            FreshnessLabel(fetchedAt: data.tasksToday.fetchedAt, error: data.tasksToday.error)
        } header: {
            Button { open(.tasks) } label: { Text("Tasks") }
        }
    }

    private var moneyBlock: some View {
        Section {
            ForEach(summary.money, id: \.name) { line in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(line.name)
                        Spacer()
                        Text(euros(line.balanceCents)).monospacedDigit()
                    }
                    if let goal = line.nextGoal {
                        ProgressView(value: Double(goal.savedCents), total: Double(max(goal.targetCents, 1))) {
                            Text(goal.title).font(.caption)
                        }
                    }
                }
            }
            FreshnessLabel(fetchedAt: data.money.fetchedAt, error: data.money.error)
        } header: {
            Button { open(.money) } label: { Text("Money") }
        }
    }

    private var capturesBlock: some View {
        Section {
            let recent = latest(data.captures.captures, count: 3, date: \.createdAt)
            if recent.isEmpty {
                Text("No captures yet").foregroundStyle(.secondary)
            }
            ForEach(recent) { capture in
                Text(capture.title ?? capture.vault).lineLimit(1)
            }
        } header: {
            Button { open(.captures) } label: { Text("Captures") }
        }
    }
}
```

- [ ] **Step 4: Tasks and money**

`Sources/App/TasksView.swift`:

```swift
import SwiftUI

struct TasksView: View {
    let data: FamilyData
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List {
                if let failure {
                    Text(failure).foregroundStyle(.red).font(.footnote)
                }
                ForEach(data.tasksToday.value?.todos ?? []) { task in
                    Button {
                        Task { await complete(task) }
                    } label: {
                        Label(task.title, systemImage: task.isOpen ? "circle" : "checkmark.circle.fill")
                    }
                    .disabled(!task.isOpen)
                }
                FreshnessLabel(fetchedAt: data.tasksToday.fetchedAt, error: data.tasksToday.error)
            }
            .navigationTitle(Text("Tasks"))
            .refreshable { await data.tasksToday.refresh() }
        }
    }

    /// Online only for now: a failed change says so and the task stays open.
    private func complete(_ task: TaskItem) async {
        do {
            try await AppAPI.completeTask(id: task.id)
            failure = nil
            await data.tasksToday.refresh()
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
```

`Sources/App/MoneyView.swift`:

```swift
import SwiftUI

struct MoneyView: View {
    let data: FamilyData

    var body: some View {
        NavigationStack {
            List {
                switch data.money.value {
                case let .kid(_, kid):
                    kidSection(kid)
                case let .parent(_, kids):
                    ForEach(kids) { kidSection($0) }
                case .none:
                    EmptyView()
                }
                FreshnessLabel(fetchedAt: data.money.fetchedAt, error: data.money.error)
            }
            .navigationTitle(Text("Money"))
            .refreshable { await data.money.refresh() }
        }
    }

    private func kidSection(_ kid: KidMoney) -> some View {
        Section(kid.displayName) {
            HStack {
                Text("Balance")
                Spacer()
                Text(euros(kid.balanceCents)).monospacedDigit()
            }
            if !kid.hasAccounts {
                Text("No bank account linked yet").foregroundStyle(.secondary)
            }
            ForEach(kid.goals.filter { !$0.archived }) { goal in
                ProgressView(value: Double(goal.savedCents), total: Double(max(goal.targetCents, 1))) {
                    HStack {
                        Text(goal.title)
                        Spacer()
                        Text("\(euros(goal.savedCents)) / \(euros(goal.targetCents))").monospacedDigit()
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 5: Captures embedded, root view**

In `ContentView`: add `var embedded = false` as the second stored property. In `body`, when `embedded`, render the selected vault only:

```swift
    var body: some View {
        Group {
            if embedded {
                if let vault = selectedVault ?? vaultStore.vaults.first {
                    vaultTab(for: vault)
                } else {
                    VaultManagementView(store: vaultStore)
                }
            } else {
                GeometryReader { geometry in
                    let landscape = geometry.size.width > geometry.size.height && geometry.size.width >= 640
                    Group {
                        if landscape { landscapeShell } else { portraitTabs }
                    }
                }
            }
        }
        // …the existing .onAppear / .task / .onChange modifiers stay attached here unchanged.
    }
```

In `vaultTab(for:)`'s `.toolbar`, add before the `EditButton` item:

```swift
                if embedded && vaultStore.vaults.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            ForEach(vaultStore.vaults) { v in
                                Button { selectedVaultKey = v.key } label: {
                                    Label(v.displayName, systemImage: v.symbolName)
                                }
                            }
                        } label: {
                            Label(vault.displayName, systemImage: "chevron.down.circle")
                        }
                    }
                }
```

`Sources/App/RootView.swift`:

```swift
import SwiftUI

/// Today first, then the sections the server allows, then Settings. A tab
/// bar on iPhone, a sidebar where the width allows.
struct RootView: View {
    @Bindable var vaultStore: VaultStore
    @State private var data = FamilyData()
    @State private var selection: AppSection = .today
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    List(data.sections, selection: selectionOptional) { section in
                        label(section).tag(section)
                    }
                    .navigationTitle(Text("Oyloo"))
                } detail: {
                    screen(selection)
                }
            } else {
                TabView(selection: $selection) {
                    ForEach(data.sections) { section in
                        screen(section).tabItem { label(section) }.tag(section)
                    }
                }
            }
        }
        .task { await data.refreshAll() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await data.refreshAll() } }
        }
        .onChange(of: data.sections) { _, sections in
            if !sections.contains(selection) { selection = .today }
        }
    }

    private var selectionOptional: Binding<AppSection?> {
        Binding(get: { selection }, set: { selection = $0 ?? .today })
    }

    @ViewBuilder
    private func screen(_ section: AppSection) -> some View {
        switch section {
        case .today: TodayView(data: data) { selection = $0 }
        case .money: MoneyView(data: data)
        case .tasks: TasksView(data: data)
        case .captures: ContentView(vaultStore: vaultStore, embedded: true)
        case .settings: VaultManagementView(store: vaultStore)
        }
    }

    private func label(_ section: AppSection) -> some View {
        switch section {
        case .today: Label("Today", systemImage: "sun.max")
        case .money: Label("Money", systemImage: "eurosign.circle")
        case .tasks: Label("Tasks", systemImage: "checklist")
        case .captures: Label("Captures", systemImage: "tray.full")
        case .settings: Label("Settings", systemImage: "gearshape")
        }
    }
}
```

In `OylooApp.body`, replace `ContentView(vaultStore: vaultStore)` with `RootView(vaultStore: vaultStore)`.

- [ ] **Step 6: Build and commit**

Run: `BUILD`. Fix any compile error only in the files of this task.

```bash
git add Sources/App
git commit -m "feat(app): Today screen and sections from the server's list"
```

---

### Task 6: Languages

**Files:**
- Create: `Sources/App/Localizable.xcstrings`
- Modify: `Sources/App/Info.plist` (`CFBundleLocalizations` = en, ru, lv)

- [ ] **Step 1: Catalog**

Create the catalog with `sourceLanguage: "en"` and `ru` and `lv` translations for every string introduced in Tasks 4–5 (titles, section labels, freshness, errors, empty states, "and %lld more", "%@ / %@"). Interpolated keys use the catalog's format specifiers (`Updated %lld min ago`, `The server answered %lld.`, `and %lld more`).

- [ ] **Step 2: Build and commit**

Run: `BUILD`; then verify the catalog was compiled into the bundle: `ls "$APP/ru.lproj" "$APP/lv.lproj"` → `Localizable.strings` (or `.stringsdict`) present.

```bash
git add Sources/App/Localizable.xcstrings Sources/App/Info.plist
git commit -m "feat(app): English, Russian and Latvian for the new screens"
```

---

### Task 7: Device check and merge

- [ ] **Step 1:** `CORETEST` and `BUILD` both green on the final tree.
- [ ] **Step 2:** Install on the owner's phone through the home Mac (copy the built `.app`, `xcrun devicectl device install app`), launch with console, confirm in the log: `captures fetched`, no decode errors; screenshot Today.
- [ ] **Step 3:** Owner confirms on the phone: Today shows tasks and money blocks with freshness, tabs match the account, Captures still shares and lists.
- [ ] **Step 4:** Only then merge to `main` and push (through the home Mac clone, as the account that has push rights), because `main` ships to family phones overnight.

---

## Self-review

- **Spec coverage:** contract and tolerant decoding — Task 1; cache per server and clearing on sign-out — Tasks 2 and 4; section visibility — Task 3 and `RootView`; Today assembly and freshness — Tasks 3 and 5; iPhone tabs and iPad sidebar — Task 5; captures embedded without nested tab bars — Task 5; online-only writes with a visible error — `TasksView.complete`; three languages — Task 6; `swift test` on Core — Tasks 1–3; device check before `main` — Task 7.
- **No placeholders:** the catalog in Task 6 lists its keys by reference to the strings of Tasks 4–5 rather than repeating them; every other step carries its code.
- **Names:** `Me`, `TasksOverview`, `TaskItem`, `MoneyOverview`, `KidMoney`, `MoneyGoal`, `MoneyMember`, `ResponseCache`, `CachedBody`, `AppSection`, `visibleSections`, `TodaySummary`, `MoneyLine`, `latest`, `Freshness`, `AppAPI`, `CachedResource`, `FamilyData`, `FreshnessLabel`, `euros`, `RootView` are used identically throughout.
