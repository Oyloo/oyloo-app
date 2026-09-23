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
