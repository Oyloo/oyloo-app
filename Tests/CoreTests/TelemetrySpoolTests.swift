import Foundation
import Testing
@testable import OylooCore

@Suite struct TelemetrySpoolTests {
    private func makeSpool(maxFiles: Int = 64, maxAge: TimeInterval = 3600) throws -> (TelemetrySpool, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spool-\(UUID().uuidString)", isDirectory: true)
        return (TelemetrySpool(directory: dir, maxFiles: maxFiles, maxAge: maxAge), dir)
    }

    @Test func takeReturnsOldestFirstAndEmptiesTheSpool() throws {
        let (spool, _) = try makeSpool()
        spool.write(Data("a".utf8), at: Date(timeIntervalSince1970: 100))
        spool.write(Data("b".utf8), at: Date(timeIntervalSince1970: 200))
        let now = Date(timeIntervalSince1970: 300)
        #expect(spool.take(now: now) == [Data("a".utf8), Data("b".utf8)])
        #expect(spool.take(now: now).isEmpty)
    }

    @Test func emptyOrMissingBodiesAreNotStored() throws {
        let (spool, _) = try makeSpool()
        spool.write(nil)
        spool.write(Data())
        #expect(spool.take().isEmpty)
    }

    @Test func keepsOnlyTheNewestFiles() throws {
        let (spool, _) = try makeSpool(maxFiles: 2)
        for i in 1...4 {
            spool.write(Data("\(i)".utf8), at: Date(timeIntervalSince1970: TimeInterval(i * 10)))
        }
        #expect(spool.take(now: Date(timeIntervalSince1970: 50)) == [Data("3".utf8), Data("4".utf8)])
    }

    @Test func forgetsBatchesOlderThanTheLimit() throws {
        let (spool, _) = try makeSpool(maxAge: 60)
        let now = Date(timeIntervalSince1970: 10_000)
        spool.write(Data("old".utf8), at: now.addingTimeInterval(-120))
        spool.write(Data("new".utf8), at: now)
        #expect(spool.take(now: now) == [Data("new".utf8)])
    }
}
