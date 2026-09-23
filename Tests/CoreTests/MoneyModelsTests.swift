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
