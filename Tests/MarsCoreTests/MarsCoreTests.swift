import XCTest
@testable import MarsCore

final class MarsCoreTests: XCTestCase {
    func temporaryStorage() throws -> Storage {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mars-test-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let storage = Storage(root: root)
        try storage.prepare()
        return storage
    }
    func testFindingWithColonAndUnicodeInPath() {
        var parser = ScanParser()
        parser.consume("/Users/test/évidence: sample.txt: Test.Virus.UNOFFICIAL FOUND")
        XCTAssertEqual(parser.findings.count, 1)
        XCTAssertEqual(parser.findings[0].path, "/Users/test/évidence: sample.txt")
        XCTAssertEqual(parser.findings[0].signature, "Test.Virus.UNOFFICIAL")
        XCTAssertEqual(parser.outcome(exitCode: 1, cancelled: false), .threatsFound)
    }
    func testNoFindingsDoesNotTurnFailureIntoSuccess() {
        let parser = ScanParser()
        XCTAssertEqual(parser.outcome(exitCode: 2, cancelled: false), .incomplete)
        XCTAssertEqual(parser.outcome(exitCode: 3, cancelled: false), .failed)
        XCTAssertEqual(parser.outcome(exitCode: 1, cancelled: false), .failed)
        XCTAssertEqual(parser.outcome(exitCode: 0, cancelled: true), .cancelled)
        XCTAssertEqual(parser.outcome(exitCode: 0, cancelled: false), .incomplete)
        var scanned = ScanParser()
        scanned.consume("Scanned files: 1")
        XCTAssertEqual(scanned.outcome(exitCode: 0, cancelled: false), .completed)
    }
    func testWarningsAndFileSummary() {
        var parser = ScanParser()
        parser.consume("Scanned files: 12345")
        parser.consume("WARNING: permission denied")
        parser.consume("/private/a: Can't open file ERROR")
        XCTAssertEqual(parser.scannedFiles, 12345)
        XCTAssertEqual(parser.warnings, 2)
        XCTAssertEqual(parser.outcome(exitCode: 0, cancelled: false), .incomplete)
    }
    func testDetectionsAndErrorsAreBothPreserved() {
        var parser = ScanParser()
        parser.consume("/a: Some.Signature FOUND")
        parser.consume("ERROR: unreadable")
        XCTAssertEqual(parser.outcome(exitCode: 2, cancelled: false), .threatsFound)
        XCTAssertEqual(parser.warnings, 1)
    }
    func testEngineLimitWarning() {
        var parser = ScanParser()
        parser.consume("/a.zip: Heuristics.Limits.Exceeded.MaxFileSize FOUND")
        XCTAssertEqual(parser.warnings, 1)
        XCTAssertEqual(parser.findings.count, 1)
    }
    func testStorageRoundTripAndPrivacy() throws {
        let storage = try temporaryStorage()
        var preferences = Preferences()
        preferences.scope = .folders; preferences.folders = ["/tmp"]; preferences.weekly = true
        try storage.save(preferences)
        XCTAssertEqual(storage.preferences(), preferences)
        var record = ScanRecord(scope: .folders, targets: ["/tmp"])
        record.finished = Date(); record.outcome = .completed; record.scannedFiles = 23
        try storage.save(record)
        XCTAssertEqual(storage.history().first?.scannedFiles, 23)
        let attrs = try FileManager.default.attributesOfItem(atPath: storage.root.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }
    func testCorruptPreferencesFallsBackSafely() throws {
        let storage = try temporaryStorage()
        try Data("not json".utf8).write(to: storage.preferencesURL)
        XCTAssertFalse(storage.preferences().scheduleEnabled)
    }
    func testMalformedHistoryIgnored() throws {
        let storage = try temporaryStorage()
        try Data("bad".utf8).write(to: storage.records.appendingPathComponent("bad.json"))
        XCTAssertTrue(storage.history().isEmpty)
    }
    func testOperationLockIsMutuallyExclusiveAndReleased() throws {
        let storage = try temporaryStorage()
        var first: OperationLock? = try OperationLock(storage: storage)
        XCTAssertNotNil(first)
        XCTAssertThrowsError(try OperationLock(storage: storage))
        first = nil
        XCTAssertNoThrow(try OperationLock(storage: storage))
    }
    func testDailyAndWeeklySchedule() {
        var preferences = Preferences()
        preferences.hour = 9; preferences.minute = 30
        let daily = Scheduler.propertyList(preferences: preferences, helper: "/Applications/Mars.app/Contents/MacOS/mars-scan", logs: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(daily["StartCalendarInterval"] as? [String: Int], ["Hour": 9, "Minute": 30])
        XCTAssertEqual(daily["ProgramArguments"] as? [String], ["/Applications/Mars.app/Contents/MacOS/mars-scan"])
        XCTAssertNil(daily["KeepAlive"])
        preferences.weekly = true; preferences.weekday = 5
        let weekly = Scheduler.propertyList(preferences: preferences, helper: "/a", logs: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(weekly["StartCalendarInterval"] as? [String: Int], ["Hour": 9, "Minute": 30, "Weekday": 5])
    }
    func testArgumentsAreNonDestructiveAndShellFree() {
        let paths = ["/tmp/folder with spaces", "/tmp/$(touch nope)"]
        let args = Engine.scanArguments(database: URL(fileURLWithPath: "/tmp/db"), targets: paths, fullMac: true)
        XCTAssertEqual(Array(args.suffix(3)), ["--"] + paths)
        XCTAssertFalse(args.contains { $0.hasPrefix("--remove") || $0.hasPrefix("--move") || $0.hasPrefix("--copy") })
        XCTAssertTrue(args.contains("--follow-dir-symlinks=0"))
        XCTAssertTrue(args.contains("--alert-exceeds-max=yes"))
    }
    func testFoldersMustExist() throws {
        var preferences = Preferences()
        preferences.scope = .folders
        XCTAssertThrowsError(try Engine.targets(for: preferences))
        preferences.folders = ["/does-not-exist-mars-\(UUID())"]
        XCTAssertThrowsError(try Engine.targets(for: preferences))
        preferences.folders = ["/tmp", "/tmp"]
        XCTAssertEqual(try Engine.targets(for: preferences), ["/tmp"])
    }
    func testConfigStaysInLocalData() throws {
        let storage = try temporaryStorage()
        try storage.writeFreshclamConfig()
        let config = try String(contentsOf: storage.config)
        XCTAssertTrue(config.contains("DatabaseDirectory \"\(storage.database.path)\""))
        XCTAssertTrue(config.contains("DatabaseMirror database.clamav.net"))
        XCTAssertFalse(config.contains("Example"))
        XCTAssertFalse(config.contains("OnUpdateExecute"))
    }
    func testProcessStreamingAndNonzeroExit() throws {
        var lines: [String] = []
        let code = try ProcessRunner.run("/bin/sh", ["-c", "printf 'first\\nsecond'; exit 2"]) { lines.append($0) }
        XCTAssertEqual(code, 2)
        XCTAssertEqual(lines, ["first", "second"])
    }
    func testCancellation() throws {
        let token = Cancellation()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { token.cancel() }
        let start = Date()
        _ = try ProcessRunner.run("/bin/sleep", ["20"], cancellation: token)
        XCTAssertTrue(token.isCancelled)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }
    func testPreCancelledOperationDoesNotLaunch() {
        let token = Cancellation(); token.cancel()
        XCTAssertThrowsError(try ProcessRunner.run("/bin/echo", ["should not run"], cancellation: token))
    }
    func testRealClamAVWithHarmlessCustomSignature() throws {
        guard ProcessInfo.processInfo.environment["MARS_CLAMAV_TESTS"] == "1" else {
            throw XCTSkip("Set MARS_CLAMAV_TESTS=1 on a Mac with ClamAV for engine integration.")
        }
        let clamscan = try XCTUnwrap(Engine.executable("clamscan"), "CI must install ClamAV")
        let storage = try temporaryStorage()
        // This is ordinary ASCII test text, not malware or an official virus database.
        let fixture = storage.root.appendingPathComponent("fixture.txt")
        try Data("MARS-SAFE-TEST-FIXTURE".utf8).write(to: fixture)
        let signature = "Mars.Test.Signature:0:*:4d4152532d534146452d544553542d46495854555245\n"
        try Data(signature.utf8).write(to: storage.database.appendingPathComponent("mars-test.ndb"))
        var parser = ScanParser()
        let code = try ProcessRunner.run(clamscan, Engine.scanArguments(database: storage.database, targets: [fixture.path], fullMac: false)) { parser.consume($0) }
        XCTAssertEqual(code, 1)
        XCTAssertEqual(parser.findings.count, 1)
        XCTAssertTrue(parser.findings.first?.signature.contains("Mars.Test.Signature") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.path), "Scan must not modify the fixture")
        let clean = storage.root.appendingPathComponent("clean.txt")
        try Data("This is a harmless clean fixture with no test signature.".utf8).write(to: clean)
        var cleanParser = ScanParser()
        let cleanCode = try ProcessRunner.run(clamscan, Engine.scanArguments(database: storage.database, targets: [clean.path], fullMac: false)) { cleanParser.consume($0) }
        XCTAssertEqual(cleanCode, 0)
        XCTAssertEqual(cleanParser.outcome(exitCode: cleanCode, cancelled: false), .completed)
    }
}
