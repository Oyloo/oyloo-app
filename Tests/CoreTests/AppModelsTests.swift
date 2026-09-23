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
