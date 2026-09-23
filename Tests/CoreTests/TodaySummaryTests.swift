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
