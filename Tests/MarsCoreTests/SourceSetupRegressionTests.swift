import XCTest
@testable import MarsCore

final class SourceSetupRegressionTests: XCTestCase {
    func storage() throws -> Storage {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mars-setup-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let value = Storage(root: root); try value.prepare(); return value
    }
    func legacySubscription(_ storage: Storage) throws {
        var sources = Catalog.defaults
        let index = try XCTUnwrap(sources.firstIndex { $0.kind == .securiteinfo })
        sources[index].acceptedTerms = true; sources[index].enabled = true
        sources[index].lastError = "The file private-securiteinfo-urls.txt could not be opened because there is no such file."
        try storage.saveSources(sources)
        XCTAssertTrue(storage.privateFeedsNeedConfiguration)
    }
    func cleanFixture(_ storage: Storage) throws -> Preferences {
        guard ProcessInfo.processInfo.environment["MARS_CLAMAV_TESTS"] == "1" else { throw XCTSkip("Native ClamAV fixture is opt-in.") }
        XCTAssertNotNil(Engine.executable("clamscan"))
        try Data("Mars.Safe.Test:0:*:4d4152532d534146452d544553542d46495854555245\n".utf8)
            .write(to: storage.database.appendingPathComponent("safe.ndb"))
        let folder = storage.root.appendingPathComponent("harmless-files")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("Ordinary clean fixture, long enough for signature inspection.".utf8).write(to: folder.appendingPathComponent("clean.txt"))
        var preferences = Preferences()
        preferences.scope = .folders; preferences.folders = [folder.path]
        // Deliberately leave updateBeforeScan true: this is the path absent from 1.0.0 tests.
        XCTAssertTrue(preferences.updateBeforeScan)
        return preferences
    }
    func testTermsAcceptanceDoesNotEnableUnconfiguredSubscription() throws {
        let storage = try storage(), manager = SourceManager(storage: storage)
        try manager.acceptTerms(id: "securiteinfo")
        let source = try XCTUnwrap(storage.sources().first { $0.id == "securiteinfo" })
        XCTAssertTrue(source.acceptedTerms)
        XCTAssertFalse(source.enabled)
        XCTAssertThrowsError(try manager.setEnabled(id: source.id, enabled: true)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Not configured"))
        }
        XCTAssertFalse(storage.sources().first { $0.id == source.id }!.enabled)
    }
    func testLegacyEnabledSubscriptionCanBeDisabledWithoutCredentials() throws {
        let storage = try storage(); try legacySubscription(storage)
        try SourceManager(storage: storage).setEnabled(id: "securiteinfo", enabled: false)
        XCTAssertFalse(try XCTUnwrap(storage.sources().first { $0.kind == .securiteinfo }).enabled)
    }
    func testMissingPrivateFileProducesSetupGuidanceNotFileReadError() throws {
        let storage = try storage(); try legacySubscription(storage)
        try FileManager.default.removeItem(at: storage.privateFeeds())
        XCTAssertThrowsError(try SourceManager(storage: storage).subscriptionURLs()) { error in
            XCTAssertTrue(error.localizedDescription.contains("Detection Sources"))
            XCTAssertFalse(error.localizedDescription.contains("private-securiteinfo-urls.txt"))
            XCTAssertFalse(error.localizedDescription.contains("no such file"))
        }
    }
    func testOptionalRefreshReturnsWarningInsteadOfAborting() throws {
        let storage = try storage(); try legacySubscription(storage)
        var lines: [String] = []
        let issues = try SourceManager(storage: storage).refreshOptionalUnlocked(storage.sources().filter { $0.kind == .securiteinfo },
            cancellation: Cancellation()) { lines.append($0) }
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].id, "securiteinfo")
        XCTAssertTrue(lines.contains { $0.contains("baseline remains available") })
        XCTAssertTrue(storage.privateFeedsNeedConfiguration)
        XCTAssertNil(storage.sources().first { $0.kind == .securiteinfo }?.lastError)
    }
    func testCancelledOptionalRefreshStillPropagatesCancellation() throws {
        let storage = try storage(); try legacySubscription(storage)
        let token = Cancellation(); token.cancel()
        XCTAssertThrowsError(try SourceManager(storage: storage).refreshOptionalUnlocked(storage.sources().filter { $0.kind == .securiteinfo }, cancellation: token) { _ in })
    }
    func testSettingsOfficialUpdateNeverTouchesOptionalSubscription() throws {
        let storage = try storage(); try legacySubscription(storage)
        var officialCalls = 0
        let engine = Engine(storage: storage, officialUpdateOverride: { _, _ in officialCalls += 1 })
        XCTAssertNoThrow(try engine.updateOfficial(cancellation: Cancellation()) { _ in })
        XCTAssertEqual(officialCalls, 1)
        XCTAssertNil(storage.sources().first { $0.kind == .securiteinfo }?.lastError, "Official-only update must not attempt this optional provider")
    }
    func testUpdateAllKeepsSuccessfulOfficialRefreshWithOptionalWarning() throws {
        let storage = try storage(); try legacySubscription(storage)
        var officialCalls = 0
        let engine = Engine(storage: storage, officialUpdateOverride: { _, _ in officialCalls += 1 })
        let issues = try engine.update(cancellation: Cancellation()) { _ in }
        XCTAssertEqual(officialCalls, 1); XCTAssertEqual(issues.count, 0)
    }
    func testDefaultAutoUpdateScanRunsRealBaselineWithMissingOptionalConfig() throws {
        let storage = try storage(); try legacySubscription(storage)
        let preferences = try cleanFixture(storage)
        var officialCalls = 0
        let engine = Engine(storage: storage, officialUpdateOverride: { _, line in
            officialCalls += 1; line("Deterministic official-refresh fixture; real clamscan follows.")
        })
        let result = try engine.scan(preferences: preferences, cancellation: Cancellation()) { _ in }
        XCTAssertEqual(officialCalls, 1)
        XCTAssertGreaterThan(result.scannedFiles, 0)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.outcome, .completed)
        XCTAssertTrue(result.baselineFinished)
        XCTAssertEqual(result.passes?.count, 1)
        XCTAssertEqual(result.warnings, 0, "Unconfigured, disabled optional sources are not scan failures")
        XCTAssertFalse(result.note.contains("no such file"))
    }
    func testScanWithoutRefreshAlsoIsolatesLegacyMissingConfig() throws {
        let storage = try storage(); try legacySubscription(storage)
        var preferences = try cleanFixture(storage); preferences.updateBeforeScan = false
        let result = try Engine(storage: storage).scan(preferences: preferences, cancellation: Cancellation()) { _ in }
        XCTAssertTrue(result.baselineFinished)
        XCTAssertEqual(result.outcome, .completed)
        XCTAssertGreaterThan(result.scannedFiles, 0)
    }
    func testUnconfiguredDisabledSourceDoesNotAffectBaselineAtAll() throws {
        let storage = try storage()
        let preferences = try cleanFixture(storage)
        let engine = Engine(storage: storage, officialUpdateOverride: { _, _ in })
        let result = try engine.scan(preferences: preferences, cancellation: Cancellation()) { _ in }
        XCTAssertEqual(result.outcome, .completed)
        XCTAssertEqual(result.passes?.count, 1)
        XCTAssertEqual(result.warnings, 0)
    }
    func testFirstAutoUpdatedYaraSourceUsesFreshNotStaleMetadata() throws {
        guard ProcessInfo.processInfo.environment["MARS_SOURCE_NETWORK_TESTS"] == "1" else { throw XCTSkip("Live pinned-pack update is opt-in.") }
        let storage = try storage()
        var preferences = try cleanFixture(storage); preferences.yaraXEnabled = true
        var sources = Catalog.defaults
        // Reproduce 1.0.0's legacy state, with consent recorded but no download yet.
        sources[0].acceptedTerms = true; sources[0].enabled = true
        try storage.saveSources(sources)
        let engine = Engine(storage: storage, officialUpdateOverride: { _, _ in })
        let result = try engine.scan(preferences: preferences, cancellation: Cancellation()) { _ in }
        let pass = try XCTUnwrap(result.passes?.first { $0.source == "Elastic Mac starter rules" })
        XCTAssertNotEqual(pass.status, "notRun")
        XCTAssertTrue(result.baselineFinished)
        XCTAssertNotNil(storage.sources()[0].updated)
    }
}
