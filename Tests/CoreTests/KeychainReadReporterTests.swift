import Testing
@testable import OylooCore

@Suite struct KeychainReadReporterTests {
    let found: Int32 = 0
    let notFound: Int32 = -25300
    let missingEntitlement: Int32 = -34018

    @Test func firstReadOfEachKeyIsReported() {
        let reporter = KeychainReadReporter()
        #expect(reporter.shouldReport(key: "sync.baseURL", status: found))
        #expect(reporter.shouldReport(key: "oyloo.vaults.v1", status: found))
    }

    @Test func repeatedReadWithTheSameOutcomeIsNot() {
        let reporter = KeychainReadReporter()
        _ = reporter.shouldReport(key: "sync.baseURL", status: found)
        #expect(!reporter.shouldReport(key: "sync.baseURL", status: found))
        #expect(!reporter.shouldReport(key: "sync.baseURL", status: found))
    }

    @Test func aChangedOutcomeIsReportedAgain() {
        // The question the line answers is "can this process read the key":
        // an item appearing or vanishing mid-process is exactly that.
        let reporter = KeychainReadReporter()
        _ = reporter.shouldReport(key: "sync.token", status: notFound)
        #expect(reporter.shouldReport(key: "sync.token", status: found))
    }

    @Test func failuresAreAlwaysReported() {
        let reporter = KeychainReadReporter()
        #expect(reporter.shouldReport(key: "sync.baseURL", status: missingEntitlement))
        #expect(reporter.shouldReport(key: "sync.baseURL", status: missingEntitlement))
    }
}
