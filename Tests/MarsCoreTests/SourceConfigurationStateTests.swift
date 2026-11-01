import XCTest
@testable import MarsCore

final class SourceConfigurationStateTests: XCTestCase {
    func storage() throws -> Storage {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mars-source-state-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let storage = Storage(root: root)
        try storage.prepare()
        return storage
    }
    func testPrepareCreatesAnEmptyPrivateConfigurationWith0600Permissions() throws {
        let storage = try storage()
        XCTAssertEqual(try Data(contentsOf: storage.privateFeeds()).count, 0)
        let attributes = try FileManager.default.attributesOfItem(atPath: storage.privateFeeds().path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertTrue(storage.privateFeedsNeedConfiguration)
    }
    func testRepeatedPreparationPreservesExistingPrivateURLs() throws {
        let storage = try storage()
        let text = "https://www.securiteinfo.com/get/signatures/private-fixture/test.ndb"
        try storage.setPrivateFeeds(text)
        try storage.prepare(); try storage.prepare()
        XCTAssertEqual(try String(contentsOf: storage.privateFeeds()), text)
        XCTAssertFalse(storage.privateFeedsNeedConfiguration)
    }
    func testLegacyEmptySubscriptionIsDisabledAndHasNoVisibleError() throws {
        let storage = try storage()
        var source = try XCTUnwrap(Catalog.defaults.first { $0.kind == .securiteinfo })
        source.enabled = true; source.acceptedTerms = true
        source.lastError = "The file private-securiteinfo-urls.txt could not be opened because there is no such file."
        try storage.saveSources([source])
        let result = try XCTUnwrap(storage.sources().first { $0.kind == .securiteinfo })
        XCTAssertFalse(result.enabled)
        XCTAssertNil(result.lastError)
        XCTAssertTrue(SourceManager(storage: storage).setupIssue(for: result, requireActive: true)?.contains("Not configured") == true)
    }
    func testWhitespaceOnlyConfigurationIsAlsoAnOrdinarySetupState() throws {
        let storage = try storage()
        try Data(" \n\t\n".utf8).write(to: storage.privateFeeds())
        XCTAssertTrue(storage.privateFeedsNeedConfiguration)
        XCTAssertThrowsError(try SourceManager(storage: storage).subscriptionURLs()) {
            XCTAssertFalse($0.localizedDescription.contains("no such file"))
        }
    }
    func testNonemptyInvalidConfigurationDoesNotHideARealError() throws {
        let storage = try storage()
        try Data("invalid nonempty fixture".utf8).write(to: storage.privateFeeds())
        var source = try XCTUnwrap(Catalog.defaults.first { $0.kind == .securiteinfo })
        source.lastError = "Actual validation failure"
        try storage.saveSources([source])
        XCTAssertFalse(storage.privateFeedsNeedConfiguration)
        XCTAssertEqual(storage.sources().first { $0.kind == .securiteinfo }?.lastError, "Actual validation failure")
        XCTAssertThrowsError(try SourceManager(storage: storage).subscriptionURLs())
    }
    func testChangingPrivateURLsRequiresValidationAndExplicitReenable() throws {
        let storage = try storage()
        var source = try XCTUnwrap(Catalog.defaults.first { $0.kind == .securiteinfo })
        source.enabled = true; source.acceptedTerms = true
        source.updated = Date(); source.files = 1; source.lastError = "Old error"
        try storage.saveSources([source])
        try storage.setPrivateFeeds("https://www.securiteinfo.com/get/signatures/private-fixture/test.ndb")
        let result = try XCTUnwrap(storage.sources().first { $0.kind == .securiteinfo })
        XCTAssertFalse(result.enabled)
        XCTAssertNil(result.updated)
        XCTAssertNil(result.lastError)
        XCTAssertEqual(result.files, 0)
        XCTAssertTrue(result.acceptedTerms)
    }
    func testRealConfigurationFailuresStillProduceWarnings() throws {
        let storage = try storage()
        try Data("invalid nonempty fixture".utf8).write(to: storage.privateFeeds())
        var source = try XCTUnwrap(Catalog.defaults.first { $0.kind == .securiteinfo })
        source.enabled = true; source.acceptedTerms = true
        try storage.saveSources([source])
        let issues = try SourceManager(storage: storage).refreshOptionalUnlocked(storage.sources().filter(\.enabled),
            cancellation: Cancellation()) { _ in }
        XCTAssertEqual(issues.count, 1)
        XCTAssertNotNil(storage.sources().first { $0.kind == .securiteinfo }?.lastError)
    }
    func testRetiredSanesecurityCannotRunButItsFilesAndHistoryArePreserved() throws {
        let storage = try storage()
        var source = DetectionSource(id: "sanesecurity", name: "Sanesecurity", engine: .clamav,
            kind: .sanesecurity, license: "Legacy", origin: "https://sanesecurity.com")
        source.enabled = true; source.acceptedTerms = true; source.lastError = "rsync transport failed"
        let active = storage.activeSource(source.id)
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        try Data("preserved legacy file".utf8).write(to: active.appendingPathComponent("legacy.hdb"))
        let record = ScanRecord(scope: .home, targets: ["/Users/demo"])
        try storage.save(record); try storage.saveSources([source])
        XCTAssertFalse(Catalog.defaults.contains { $0.kind == .sanesecurity })
        XCTAssertFalse(storage.sources().contains { $0.kind == .sanesecurity })
        XCTAssertTrue(FileManager.default.fileExists(atPath: active.appendingPathComponent("legacy.hdb").path))
        XCTAssertEqual(storage.history().first?.id, record.id)
        XCTAssertThrowsError(try SourceManager(storage: storage).update(id: source.id, cancellation: Cancellation()) { _ in })
    }
}
