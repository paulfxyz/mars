import XCTest
@testable import MarsCore

final class AppUpdaterTests: XCTestCase {
    func metadata(version: String = "1.2.0", archiveHost: String = "https://github.com/paulfxyz/mars", prerelease: Bool = false, checksum: Bool = true) throws -> Data {
        var assets: [[String: String]] = [
            ["name": "Mars-\(version)-macOS-universal.zip", "browser_download_url": "\(archiveHost)/releases/download/v\(version)/Mars-\(version)-macOS-universal.zip"]
        ]
        if checksum { assets.append(["name": "SHA256SUMS.txt", "browser_download_url": "https://github.com/paulfxyz/mars/releases/download/v\(version)/SHA256SUMS.txt"]) }
        return try JSONSerialization.data(withJSONObject: ["tag_name": "v\(version)", "draft": false, "prerelease": prerelease, "assets": assets])
    }
    func testVersionComparisonIsNumericNotLexicographic() throws {
        XCTAssertGreaterThan(try XCTUnwrap(AppVersion("1.10.0")), try XCTUnwrap(AppVersion("1.9.9")))
        XCTAssertGreaterThan(try XCTUnwrap(AppVersion("2.0.0")), try XCTUnwrap(AppVersion("1.99.99")))
        for bad in ["1.2", "v1.2.3", "1.2.3-beta", "01.2.3", "../1.2.3", "1.-2.0", "1.2.3.4"] { XCTAssertNil(AppVersion(bad)) }
    }
    func testStableOfficialReleaseParses() throws {
        let release = try AppUpdater.parseRelease(metadata())
        XCTAssertEqual(release.version.description, "1.2.0")
        XCTAssertEqual(release.archiveName, "Mars-1.2.0-macOS-universal.zip")
        XCTAssertEqual(release.page.absoluteString, "https://github.com/paulfxyz/mars/releases/tag/v1.2.0")
    }
    func testExternalRepositoryOrMissingChecksumsRejected() throws {
        XCTAssertThrowsError(try AppUpdater.parseRelease(metadata(archiveHost: "https://evil.example/paulfxyz/mars")))
        XCTAssertThrowsError(try AppUpdater.parseRelease(metadata(archiveHost: "https://github.com/other/repository")))
        XCTAssertThrowsError(try AppUpdater.parseRelease(metadata(checksum: false)))
        XCTAssertThrowsError(try AppUpdater.parseRelease(metadata(prerelease: true)))
    }
    func testChecksumMustMatchExactArchiveAndBeUnique() throws {
        let hash = String(repeating: "a", count: 64), name = "Mars-1.2.0-macOS-universal.zip"
        XCTAssertEqual(try AppUpdater.expectedHash(manifest: "\(hash)  \(name)\n", archiveName: name), hash)
        XCTAssertThrowsError(try AppUpdater.expectedHash(manifest: "\(hash)  other.zip", archiveName: name))
        XCTAssertThrowsError(try AppUpdater.expectedHash(manifest: "\(hash)  \(name)\n\(hash)  \(name)", archiveName: name))
        XCTAssertThrowsError(try AppUpdater.expectedHash(manifest: "not-a-hash  \(name)", archiveName: name))
    }
    func testTamperedDownloadRejected() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("mars-update-\(UUID()).zip")
        defer { try? FileManager.default.removeItem(at: file) }
        let data = Data("harmless archive test bytes".utf8)
        try data.write(to: file)
        XCTAssertNoThrow(try AppUpdater.verify(file: file, expected: Catalog.sha256(data)))
        XCTAssertThrowsError(try AppUpdater.verify(file: file, expected: String(repeating: "0", count: 64)))
    }
    func testCancelledVerificationDoesNotAcceptFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("mars-update-\(UUID()).zip")
        defer { try? FileManager.default.removeItem(at: file) }
        let data = Data("test bytes".utf8); try data.write(to: file)
        let token = Cancellation(); token.cancel()
        XCTAssertThrowsError(try AppUpdater.verify(file: file, expected: Catalog.sha256(data), cancellation: token))
    }
    func testExternallyWrittenResponseUsesFreshFileAttributes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mars-response-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source")
        let target = folder.appendingPathComponent("response")
        _ = try? target.resourceValues(forKeys: [.fileSizeKey])
        try Data("response bytes".utf8).write(to: source)
        XCTAssertEqual(try ProcessRunner.run("/bin/cp", [source.path, target.path]), 0)
        XCTAssertNoThrow(try AppUpdater.validateResponseFile(target, maxBytes: 100))
        XCTAssertThrowsError(try AppUpdater.validateResponseFile(target, maxBytes: 1))
        try Data().write(to: target)
        XCTAssertThrowsError(try AppUpdater.validateResponseFile(target, maxBytes: 100))
    }
    func testLiveOfficialUpdateMetadataDownloadChecksumAndQuarantine() throws {
        guard ProcessInfo.processInfo.environment["MARS_SOURCE_NETWORK_TESTS"] == "1" else { throw XCTSkip("Public release update test is opt-in.") }
        let storage = Storage(root: FileManager.default.temporaryDirectory.appendingPathComponent("mars-updater-\(UUID())"))
        defer { try? FileManager.default.removeItem(at: storage.root) }
        let updater = AppUpdater(storage: storage)
        let release = try updater.latest()
        let archive = try updater.download(release)
        XCTAssertEqual(archive.lastPathComponent, release.archiveName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
        XCTAssertNotNil(try archive.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties)
        // The only output is an opaque ZIP, not an installed or extracted application.
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.root.appendingPathComponent("Mars.app").path))
    }
}
