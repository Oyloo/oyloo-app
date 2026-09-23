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
