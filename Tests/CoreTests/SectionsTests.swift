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
