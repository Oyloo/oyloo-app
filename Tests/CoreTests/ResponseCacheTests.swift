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
