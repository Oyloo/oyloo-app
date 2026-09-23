import Foundation
import Testing
@testable import OylooCore

@Suite struct TaskLogicTests {
    @Test func fullOverviewDecodes() throws {
        let json = """
        {"today":"2026-09-23","view":"next","tag":"finance","counts":{"today":2,"next":5},
         "todos":[{"id":"t1","title":"Pay","status":"waiting","important":true,"due":"2026-09-20",
                   "circleId":"family","priority":"P1","overdue":true,"urgent":true,
                   "waitingOn":"bank","tags":["finance"],"notes":null,"extra":1}],
         "tags":[{"id":"finance","label":"финансы"}],"circles":[{"id":"family","label":"Семья"}]}
        """
        let o = try AppJSON.decoder.decode(TasksOverview.self, from: Data(json.utf8))
        #expect(o.tag == "finance")
        #expect(o.tags == [TaskTag(id: "finance", label: "финансы")])
        #expect(o.circles == [TaskCircle(id: "family", label: "Семья")])
        #expect(o.todos[0].waitingOn == "bank")
        #expect(o.todos[0].tags == ["finance"])
    }

    @Test func minimalCachedOverviewStillReads() throws {
        let json = """
        {"today":"2026-09-23","view":"today","counts":{},
         "todos":[{"id":"t1","title":"A","status":"next","important":false,"priority":"P4","overdue":false}]}
        """
        let o = try AppJSON.decoder.decode(TasksOverview.self, from: Data(json.utf8))
        #expect(o.tag == nil && o.tags.isEmpty && o.circles.isEmpty)
        #expect(o.todos[0].due == nil && o.todos[0].tags.isEmpty && o.todos[0].waitingOn == nil)
    }

    @Test func dueWording() {
        let today = "2026-09-30"
        #expect(DueWording.make(due: "2026-09-30", today: today) == .today)
        #expect(DueWording.make(due: "2026-10-01", today: today) == .tomorrow)
        #expect(DueWording.make(due: "2026-10-03", today: today) == .inDays(3))
        #expect(DueWording.make(due: "2026-10-08", today: today) == .date("2026-10-08"))
        #expect(DueWording.make(due: "2026-09-28", today: today) == .overdue(2))
        #expect(DueWording.make(due: "2025-12-31", today: "2026-01-01") == .overdue(1))
        #expect(DueWording.make(due: "garbage", today: today) == nil)
    }

    @Test func swipeActionsDependOnStatus() {
        #expect(statusActions(for: "next") == ["waiting", "someday", "dropped"])
        #expect(statusActions(for: "waiting") == ["next", "someday", "dropped"])
        #expect(statusActions(for: "someday") == ["next", "waiting", "dropped"])
        #expect(statusActions(for: "inbox") == ["next", "waiting", "someday", "dropped"])
        #expect(statusActions(for: "done") == ["next"])
        #expect(statusActions(for: "dropped") == ["next"])
    }

    @Test func createBodySkipsEmptyOptionals() {
        let draft = TaskDraft(title: "  Buy milk ", due: nil, important: false, circleId: nil, tags: [])
        #expect(draft.createBody as NSDictionary == ["title": "Buy milk", "important": false, "tags": []] as NSDictionary)
        let full = TaskDraft(title: "X", due: "2026-10-01", important: true, circleId: "family", tags: ["finance"])
        #expect(full.createBody as NSDictionary == ["title": "X", "important": true, "tags": ["finance"],
                                                    "due": "2026-10-01", "circleId": "family"] as NSDictionary)
    }

    @Test func draftDecodesParseAnswer() throws {
        let json = #"{"title":"Купить молоко","due":null,"important":true,"circleId":null,"tags":[]}"#
        let d = try AppJSON.decoder.decode(TaskDraft.self, from: Data(json.utf8))
        #expect(d == TaskDraft(title: "Купить молоко", due: nil, important: true, circleId: nil, tags: []))
    }

    @Test func viewsInServerOrder() {
        #expect(TaskView.allCases.map(\.rawValue) == ["today", "overdue", "next", "waiting", "someday", "done"])
    }
}
