import Foundation
import CryptoKit
import CoreServices

public struct AppVersion: Comparable, Equatable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public var description: String { "\(major).\(minor).\(patch)" }
    public static let fallback = "1.1.0"
    public static var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? fallback }
    public init?(_ value: String) {
        let fields = value.split(separator: ".", omittingEmptySubsequences: false)
        guard fields.count == 3, fields.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) && ($0.count == 1 || $0.first != "0") }),
              let major = Int(fields[0]), let minor = Int(fields[1]), let patch = Int(fields[2]) else { return nil }
        self.major = major; self.minor = minor; self.patch = patch
    }
    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

public struct AppRelease: Equatable {
    public let version: AppVersion
    public let page: URL
    public let archive: URL
    public let checksums: URL
    public var archiveName: String { "Mars-\(version)-macOS-universal.zip" }
}

/// Manual, explicit update checks only. Downloads remain opaque ZIP files: this code never
/// extracts, executes, replaces, or quits the running app.
public struct AppUpdater {
    public let storage: Storage
    public init(storage: Storage = Storage()) { self.storage = storage }
    private struct APIAsset: Decodable { let name: String; let browser_download_url: String }
    private struct APIRelease: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let assets: [APIAsset]
    }
    public static func parseRelease(_ data: Data) throws -> AppRelease {
        let value = try JSONDecoder().decode(APIRelease.self, from: data)
        guard !value.draft, !value.prerelease, value.tag_name.hasPrefix("v"),
              let version = AppVersion(String(value.tag_name.dropFirst())),
              value.tag_name == "v\(version)" else {
            throw MarsError.message("The update service did not return a stable Mars release.")
        }
        let archiveName = "Mars-\(version)-macOS-universal.zip"
        let base = "https://github.com/paulfxyz/mars/releases/download/v\(version)/"
        func asset(_ name: String) throws -> URL {
            let matches = value.assets.filter { $0.name == name }
            guard matches.count == 1, matches[0].browser_download_url == base + name,
                  let url = URL(string: matches[0].browser_download_url) else {
                throw MarsError.message("The release is missing an expected Mars download or points outside the official repository. No update was downloaded.")
            }
            return url
        }
        return try AppRelease(version: version, page: URL(string: "https://github.com/paulfxyz/mars/releases/tag/v\(version)")!,
                              archive: asset(archiveName), checksums: asset("SHA256SUMS.txt"))
    }
    public static func expectedHash(manifest: String, archiveName: String) throws -> String {
        var found: [String] = []
        for line in manifest.split(whereSeparator: \.isNewline) {
            let fields = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard fields.count == 2 else { continue }
            var name = String(fields[1]).trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("*") { name.removeFirst() }
            if name == archiveName {
                let hash = String(fields[0]).lowercased()
                guard hash.count == 64, hash.allSatisfy({ "0123456789abcdef".contains($0) }) else {
                    throw MarsError.message("The update checksum is malformed. The download was not accepted.")
                }
                found.append(hash)
            }
        }
        guard found.count == 1 else { throw MarsError.message("A unique checksum for this exact Mars archive is missing. The download was not accepted.") }
        return found[0]
    }
    public static func verify(file: URL, expected: String, cancellation: Cancellation = Cancellation()) throws {
        if cancellation.isCancelled { throw MarsError.message("Update download cancelled.") }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            if cancellation.isCancelled { throw MarsError.message("Update download cancelled.") }
            hash.update(data: chunk)
        }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == expected.lowercased() else { throw MarsError.message("The update failed its SHA-256 integrity check. Nothing was installed; download again from the official release page.") }
    }
    private func folder() throws -> URL {
        try storage.prepare()
        let folder = storage.root.appendingPathComponent("Updates", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return folder
    }
    private func fetch(_ url: URL, to target: URL, maxBytes: Int, cancellation: Cancellation) throws {
        let code = try ProcessRunner.run("/usr/bin/curl", ["--disable", "--fail", "--silent", "--show-error", "--location",
            "--proto", "=https", "--proto-redir", "=https", "--connect-timeout", "15", "--max-time", "180",
            "--max-filesize", "\(maxBytes)", "--user-agent", "Mars/\(AppVersion.current)",
            "--output", target.path, url.absoluteString], cancellation: cancellation, timeout: 190)
        if cancellation.isCancelled { throw MarsError.message("Update check or download cancelled.") }
        guard code == 0 else { throw MarsError.message("Could not contact GitHub or download this update (transport \(code)). Check the connection and try later; GitHub can also rate-limit update checks.") }
        try Self.validateResponseFile(target, maxBytes: maxBytes)
    }
    static func validateResponseFile(_ target: URL, maxBytes: Int) throws {
        // curl writes outside Foundation. Read fresh filesystem attributes rather
        // than possibly stale resource metadata cached on a previously absent URL.
        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0, size <= maxBytes else { throw MarsError.message("The update response is empty or exceeds the download limit.") }
    }
    public func latest(cancellation: Cancellation = Cancellation()) throws -> AppRelease {
        let temporary = try folder().appendingPathComponent("release-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try fetch(URL(string: "https://api.github.com/repos/paulfxyz/mars/releases/latest")!, to: temporary,
                  maxBytes: 1024 * 1024, cancellation: cancellation)
        return try Self.parseRelease(Data(contentsOf: temporary))
    }
    public func download(_ release: AppRelease, cancellation: Cancellation = Cancellation()) throws -> URL {
        let base = "https://github.com/paulfxyz/mars/releases/download/v\(release.version)/"
        guard release.archive.absoluteString == base + release.archiveName,
              release.checksums.absoluteString == base + "SHA256SUMS.txt" else {
            throw MarsError.message("Refusing an update outside the official Mars repository.")
        }
        let updates = try folder()
        let stage = updates.appendingPathComponent("download-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: stage) }
        let manifest = stage.appendingPathComponent("SHA256SUMS.txt")
        try fetch(release.checksums, to: manifest, maxBytes: 1024 * 1024, cancellation: cancellation)
        let expected = try Self.expectedHash(manifest: String(contentsOf: manifest), archiveName: release.archiveName)
        let archive = stage.appendingPathComponent(release.archiveName + ".part")
        try fetch(release.archive, to: archive, maxBytes: 256 * 1024 * 1024, cancellation: cancellation)
        try Self.verify(file: archive, expected: expected, cancellation: cancellation)
        if cancellation.isCancelled { throw MarsError.message("Update download cancelled.") }
        // A curl download does not automatically receive browser-style quarantine metadata.
        // Preserve the normal macOS approval path instead of bypassing Gatekeeper on extraction.
        var quarantined = archive
        var values = URLResourceValues()
        values.quarantineProperties = [
            kLSQuarantineAgentNameKey as String: "Mars",
            kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload,
            kLSQuarantineDataURLKey as String: release.archive as NSURL,
            kLSQuarantineOriginURLKey as String: release.page as NSURL
        ]
        try quarantined.setResourceValues(values)
        let final = updates.appendingPathComponent(release.archiveName)
        if FileManager.default.fileExists(atPath: final.path) { try FileManager.default.removeItem(at: final) }
        try FileManager.default.moveItem(at: archive, to: final)
        return final
    }
}
