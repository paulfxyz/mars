import XCTest
@testable import MarsCore

final class SourceAndDualEngineTests: XCTestCase {
    func storage() throws -> Storage {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mars-1-tests-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let storage = Storage(root: root); try storage.prepare(); return storage
    }
    func engines() throws {
        guard ProcessInfo.processInfo.environment["MARS_CLAMAV_TESTS"] == "1" else { throw XCTSkip("Native engine integration is opt-in.") }
        XCTAssertNotNil(Engine.executable("clamscan")); XCTAssertNotNil(Engine.executable("yr"))
    }
    func testOptionalPreferencesDecodeOldVersion() throws {
        let json = #"{"scope":"home","folders":[],"scheduleEnabled":false,"weekly":false,"weekday":1,"hour":12,"minute":0,"updateBeforeScan":true}"#
        let value = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        XCTAssertNil(value.yaraXEnabled)
    }
    func testOldFindingAndReportDecode() throws {
        var record = ScanRecord(scope: .home, targets: ["/tmp"])
        record.findings = [Finding(path: "/tmp/file", signature: "Old.Signature")]
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ScanRecord.self, from: data)
        XCTAssertNil(decoded.passes); XCTAssertNil(decoded.findings[0].engine)
        XCTAssertTrue(Interpretation.summary(decoded).contains("could not complete"))
    }
    func testUnofficialSourcesAreOptIn() {
        XCTAssertEqual(Catalog.defaults.count, 3)
        XCTAssertTrue(Catalog.defaults.allSatisfy { !$0.enabled && !$0.acceptedTerms })
        XCTAssertEqual(Set(Catalog.defaults.map(\.id)).count, 3)
    }
    func testTamperedPinnedDownloadIsRejected() {
        XCTAssertThrowsError(try Catalog.check(Data("tampered".utf8), expected: String(repeating: "0", count: 64)))
        let data = Data("verified".utf8)
        XCTAssertNoThrow(try Catalog.check(data, expected: Catalog.sha256(data)))
        XCTAssertThrowsError(try Catalog.check(Data(), expected: Catalog.sha256(Data())))
    }
    func testSecretURLsRestrictedToOfficialHTTPS() throws {
        XCTAssertEqual(try SourceManager.validateFeedURLs("https://www.securiteinfo.com/get/signatures/private/test.ndb").count, 1)
        for bad in ["http://www.securiteinfo.com/get/signatures/a.ndb", "https://evil.example/get/signatures/a.ndb",
                    "https://www.securiteinfo.com.evil.example/get/signatures/a.ndb", "https://www.securiteinfo.com:8443/get/signatures/a.ndb",
                    "https://user:password@www.securiteinfo.com/get/signatures/a.ndb", "file:///tmp/db.ndb", ""] {
            XCTAssertThrowsError(try SourceManager.validateFeedURLs(bad))
        }
    }
    func testPrivateFeedsAreSeparateAndUserOnly() throws {
        let storage = try storage()
        try storage.setPrivateFeeds("https://www.securiteinfo.com/get/signatures/private-account/test.ndb")
        let attrs = try FileManager.default.attributesOfItem(atPath: storage.privateFeeds().path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try storage.saveSources(Catalog.defaults)
        XCTAssertFalse(try String(contentsOf: storage.sourceSettings).contains("private-account"))
    }
    func testPromotionAndRollbackPreservePrevious() throws {
        let storage = try storage(), manager = SourceManager(storage: storage)
        let source = Catalog.defaults[0]
        let parent = storage.sourceDirectory(source.id)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        for text in ["first", "second"] {
            let stage = parent.appendingPathComponent("stage-\(UUID())")
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
            try Data(text.utf8).write(to: stage.appendingPathComponent("rule.yar"))
            try manager.promote(source, staged: stage)
        }
        XCTAssertEqual(try String(contentsOf: storage.activeSource(source.id).appendingPathComponent("rule.yar")), "second")
        try manager.rollback(id: source.id)
        XCTAssertEqual(try String(contentsOf: storage.activeSource(source.id).appendingPathComponent("rule.yar")), "first")
    }
    func testYaraJSONKeepsExactAttributionAndUnicode() {
        var parser = YaraParser()
        parser.consume(#"{"path":"/tmp/évidence.bin","rules":[{"identifier":"Mac_Pattern","namespace":"default"}]}"#, source: "Reviewed pack")
        XCTAssertEqual(parser.findings.count, 1)
        XCTAssertEqual(parser.findings[0].source, "Reviewed pack")
        XCTAssertEqual(parser.findings[0].engine, "YARA-X")
        XCTAssertEqual(parser.findings[0].path, "/tmp/évidence.bin")
        parser.consume("error: unreadable file", source: "Reviewed pack")
        XCTAssertEqual(parser.warnings, 1)
    }
    func testYaraPlanSkipsLargeFilesSymlinksAndNestedDuplicates() throws {
        let storage = try storage()
        let folder = storage.root.appendingPathComponent("fixtures")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("one".utf8).write(to: folder.appendingPathComponent("small.txt"))
        let huge = folder.appendingPathComponent("huge.bin")
        FileManager.default.createFile(atPath: huge.path, contents: nil)
        let handle = try FileHandle(forWritingTo: huge); try handle.truncate(atOffset: UInt64(YaraPlan.sizeLimit + 1)); try handle.close()
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("alias"), withDestinationURL: folder.appendingPathComponent("small.txt"))
        let plan = try YaraPlan.build(targets: [folder.path, folder.path], fullMac: false, storage: storage, cancellation: Cancellation()) { _, _ in }
        XCTAssertEqual(plan.candidates, 1); XCTAssertEqual(plan.skipped, 2)
        XCTAssertEqual(try String(contentsOf: plan.list).split(separator: "\n").count, 1)
        XCTAssertTrue(YaraPlan.excluded("/System/Volumes/Data/Volumes/External/a", fullMac: true))
        XCTAssertFalse(YaraPlan.excluded("/Volumes/External/a", fullMac: false))
    }
    func testCancelledEnumerationStops() throws {
        let storage = try storage()
        let token = Cancellation(); token.cancel()
        XCTAssertThrowsError(try YaraPlan.build(targets: [storage.root.path], fullMac: false, storage: storage, cancellation: token) { _, _ in })
    }
    func testNewbieGuidanceDoesNotCallMatchesConfirmedInfections() {
        var record = ScanRecord(scope: .home, targets: ["/tmp"])
        record.outcome = .threatsFound; record.findings = [Finding(path: "/tmp/a", signature: "Rule")]
        XCTAssertTrue(Interpretation.summary(record).contains("false positive"))
        XCTAssertTrue(Interpretation.nextSteps(record).contains { $0.contains("Do not open") })
        record.outcome = .completed
        XCTAssertTrue(Interpretation.summary(record).contains("does not prove"))
    }
    func testPinnedSanesecurityKeyBuildsIsolatedVerificationKeyring() throws {
        try engines()
        let gpg = try XCTUnwrap(Engine.executable("gpg")), storage = try storage()
        let key = storage.root.appendingPathComponent("vendor.asc")
        try Data(SourceManager.sanesecurityKey.utf8).write(to: key)
        let ring = storage.root.appendingPathComponent("vendor.gpg")
        let result = try ProcessRunner.run(gpg, ["--no-options", "--homedir", storage.root.path, "--batch", "--dearmor", "--output", ring.path, key.path])
        XCTAssertEqual(result, 0)
        var fingerprints = ""
        let inspect = try ProcessRunner.run(gpg, ["--no-options", "--homedir", storage.root.path, "--batch", "--show-keys", "--with-colons", ring.path]) { fingerprints += $0 }
        XCTAssertEqual(inspect, 0)
        XCTAssertTrue(fingerprints.contains("4E025A1CBA90A0653F38D2D8D691DED931EA4D9E"))
    }
    func testRealDualEnginePipelineAndSourceAttribution() throws {
        try engines()
        let storage = try storage()
        let fixtures = storage.root.appendingPathComponent("fixtures")
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: false)
        try Data("MARS-SAFE-TEST-FIXTURE".utf8).write(to: fixtures.appendingPathComponent("test.txt"))
        let ndb = "Mars.Test.Signature:0:*:4d4152532d534146452d544553542d46495854555245\n"
        try Data(ndb.utf8).write(to: storage.database.appendingPathComponent("test.ndb"))
        let rule = storage.root.appendingPathComponent("safe.yar")
        try Data(#"rule Mars_Safe_Test { strings: $a = "MARS-SAFE-TEST-FIXTURE" condition: $a }"#.utf8).write(to: rule)
        try SourceManager(storage: storage).importFiles([rule], name: "Harmless YARA pack", engine: .yaraX, cancellation: Cancellation()) { _ in }
        var preferences = Preferences()
        preferences.scope = .folders; preferences.folders = [fixtures.path]
        preferences.updateBeforeScan = false; preferences.yaraXEnabled = true
        let record = try Engine(storage: storage).scan(preferences: preferences, cancellation: Cancellation()) { _ in }
        XCTAssertEqual(record.outcome, .threatsFound)
        XCTAssertEqual(record.passes?.count, 2)
        XCTAssertTrue(record.findings.contains { $0.engine == "ClamAV" && $0.source == "Official ClamAV" })
        XCTAssertTrue(record.findings.contains { $0.engine == "YARA-X" && $0.source == "Harmless YARA pack" })
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixtures.appendingPathComponent("test.txt").path))
        XCTAssertEqual(storage.history().first?.passes?.count, 2)
    }
    func testMissingSecondEngineSourceIsNotSilentlyClean() throws {
        try engines()
        let storage = try storage()
        try Data("Mars.Test:0:*:4d4152532d534146452d544553542d46495854555245\n".utf8).write(to: storage.database.appendingPathComponent("test.ndb"))
        let folder = storage.root.appendingPathComponent("fixtures")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("Ordinary clean fixture text with enough bytes.".utf8).write(to: folder.appendingPathComponent("clean.txt"))
        var preferences = Preferences(); preferences.scope = .folders; preferences.folders = [folder.path]
        preferences.updateBeforeScan = false; preferences.yaraXEnabled = true
        let record = try Engine(storage: storage).scan(preferences: preferences, cancellation: Cancellation()) { _ in }
        XCTAssertEqual(record.outcome, .incomplete)
        XCTAssertTrue(record.coverageNotes?.contains { $0.contains("no YARA-X source") } == true)
    }
    func testInvalidRulesNeverReplaceActiveSource() throws {
        try engines()
        let storage = try storage()
        let file = storage.root.appendingPathComponent("bad.yar")
        try Data("not a yara rule".utf8).write(to: file)
        XCTAssertThrowsError(try SourceManager(storage: storage).importFiles([file], name: "Bad", engine: .yaraX, cancellation: Cancellation()) { _ in })
        XCTAssertEqual(storage.sources().count, Catalog.defaults.count)
    }
    func testYaraIncludesAreRejected() throws {
        try engines()
        let storage = try storage(), file = storage.root.appendingPathComponent("includes.yar")
        try Data("include \"/etc/passwd\"\n".utf8).write(to: file)
        XCTAssertThrowsError(try SourceManager(storage: storage).importFiles([file], name: "Unsafe include", engine: .yaraX, cancellation: Cancellation()) { _ in })
    }
    func testLivePinnedElasticDownloadAndCompile() throws {
        guard ProcessInfo.processInfo.environment["MARS_SOURCE_NETWORK_TESTS"] == "1" else { throw XCTSkip("Opt-in network source verification.") }
        try engines()
        let storage = try storage()
        var sources = Catalog.defaults; sources[0].acceptedTerms = true
        try storage.saveSources(sources)
        try SourceManager(storage: storage).update(id: "elastic-mac", cancellation: Cancellation()) { _ in }
        XCTAssertEqual(storage.sources()[0].files, 4)
        XCTAssertEqual(storage.sources()[0].revision, Catalog.elasticRevision)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.activeSource("elastic-mac").appendingPathComponent("LICENSE.txt").path))
    }
    func testLiveSanesecurityDownloadVerifyAndLoad() throws {
        guard ProcessInfo.processInfo.environment["MARS_SOURCE_NETWORK_TESTS"] == "1" else { throw XCTSkip("Opt-in network source verification.") }
        try engines()
        let storage = try storage()
        var sources = Catalog.defaults
        sources[1].acceptedTerms = true
        try storage.saveSources(sources)
        // The provider's DNS rotates rsync mirrors. Retry only transport
        // failures; never retry away a signature, engine, or assertion failure.
        for attempt in 1...3 {
            do {
                try SourceManager(storage: storage).update(id: "sanesecurity", cancellation: Cancellation()) { _ in }
                break
            } catch {
                guard error.localizedDescription.hasPrefix("Sanesecurity transport failed") else { throw error }
                if attempt == 3 {
                    let source = try XCTUnwrap(storage.sources().first { $0.id == "sanesecurity" })
                    XCTAssertNil(source.updated, "A failed transport must never activate unverified data")
                    XCTAssertFalse(FileManager.default.fileExists(atPath: storage.activeSource("sanesecurity").path))
                    throw XCTSkip("Provider rsync transport unavailable after three attempts. Live vendor verification was NOT established; no data was activated.")
                }
                print("Sanesecurity live transport attempt \(attempt) failed; retrying the provider mirror.")
            }
        }
        let source = try XCTUnwrap(storage.sources().first { $0.id == "sanesecurity" })
        XCTAssertEqual(source.files, 4)
        XCTAssertTrue(source.revision?.contains("signed payload dates") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.activeSource("sanesecurity").appendingPathComponent("rogue.hdb").path))
    }
    func testTransportDeadlineDoesNotPretendUserCancelled() throws {
        let token = Cancellation(), start = Date()
        let code = try ProcessRunner.run("/bin/sleep", ["20"], cancellation: token, timeout: 0.2)
        XCTAssertNotEqual(code, 0)
        XCTAssertFalse(token.isCancelled)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }
}
