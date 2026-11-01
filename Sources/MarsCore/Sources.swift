import Foundation
import CryptoKit

public enum DetectionEngine: String, Codable, CaseIterable {
    case clamav = "ClamAV", yaraX = "YARA-X"
}
public enum SourceKind: String, Codable {
    case elastic, sanesecurity, securiteinfo, local
}
public struct DetectionSource: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var engine: DetectionEngine
    public var kind: SourceKind
    public var enabled = false
    public var license: String
    public var origin: String
    public var updated: Date?
    public var revision: String?
    public var lastError: String?
    public var acceptedTerms = false
    public var files = 0
    public init(id: String, name: String, engine: DetectionEngine, kind: SourceKind, license: String, origin: String) {
        self.id = id; self.name = name; self.engine = engine; self.kind = kind; self.license = license; self.origin = origin
    }
    public var explanation: String {
        switch kind {
        case .elastic: return "Four curated Mac malware rule files from Elastic Security, pinned to a reviewed commit and SHA-256 hashes. Not a comprehensive Mac threat database."
        case .sanesecurity: return "Legacy source: automatic Sanesecurity downloads have been removed. Trusted definitions can still be imported manually."
        case .securiteinfo: return "Your own licensed HTTPS signature URLs. Paid access may be required; free Basic is intended for installation validation. No subscription or credentials are shared by Mars."
        case .local: return "User-imported rules or definitions. You are responsible for their provenance, license, quality, and future refreshes."
        }
    }
}

public enum Catalog {
    public static let elasticRevision = "c7b3b2eb7fe9a0c73282003d81da4c0e2d32941d"
    public static let elasticFiles: [(String, String)] = [
        ("MacOS_Backdoor_Applejeus.yar", "d4bd1ca00aa93dad31090ec35752fa45cf53ab50f2a4c52fd7b98d0f84b0aab6"),
        ("MacOS_Trojan_Adload.yar", "aaa0dde294622440b6df70b167870447bb5759bb0c6ff667bea56162b26471c2"),
        ("MacOS_Trojan_BeaverTail.yar", "2d455cc06c70002a7a4c718654c04ed0a3e2f753acae931c234ce08651b60708"),
        ("MacOS_Trojan_KandyKorn.yar", "eda0093e0b10ab204251359fa56dd9dc2c7c8c6419109d331541cf9721e962ee")
    ]
    public static var defaults: [DetectionSource] {
        [
            DetectionSource(id: "elastic-mac", name: "Elastic Mac starter rules", engine: .yaraX, kind: .elastic,
                            license: "Elastic License 2.0; separate from Mars MIT", origin: "https://github.com/elastic/protections-artifacts"),
            DetectionSource(id: "securiteinfo", name: "SecuriteInfo subscription", engine: .clamav, kind: .securiteinfo,
                            license: "Your subscription terms; no redistribution", origin: "https://www.securiteinfo.com/clamav-antivirus/faq-clamav-unofficial-signatures_en.shtml")
        ]
    }
    public static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    public static func check(_ data: Data, expected: String) throws {
        guard !data.isEmpty, sha256(data) == expected.lowercased() else { throw MarsError.message("Downloaded content failed its pinned SHA-256 check. The previous source is untouched.") }
    }
}

extension Storage {
    public var sourceRoot: URL { root.appendingPathComponent("Sources", isDirectory: true) }
    public var sourceSettings: URL { root.appendingPathComponent("sources.json") }
    public func sources() -> [DetectionSource] {
        guard let data = try? Data(contentsOf: sourceSettings), let stored = try? JSONDecoder().decode([DetectionSource].self, from: data) else { return Catalog.defaults }
        // Retire the unreliable automatic rsync integration, including legacy
        // enabled profiles. Keep downloaded files and historical reports intact.
        let supported = stored.filter { $0.kind != .sanesecurity }
        return (supported + Catalog.defaults.filter { base in !supported.contains { $0.id == base.id } }).map { source in
            var value = source
            if value.kind == .securiteinfo && privateFeedsNeedConfiguration {
                value.enabled = false
                value.lastError = nil
                value.updated = nil
                value.revision = nil
                value.files = 0
            }
            return value
        }
    }
    public func saveSources(_ sources: [DetectionSource]) throws {
        try prepare()
        try JSONEncoder().encode(sources).write(to: sourceSettings, options: .atomic)
    }
    /// Called only after the shared operation lock has been acquired. Persist
    /// effective retirement/setup state so old enabled flags cannot revive later.
    func migrateSourceConfigurationUnlocked() throws {
        guard let data = try? Data(contentsOf: sourceSettings),
              let stored = try? JSONDecoder().decode([DetectionSource].self, from: data) else { return }
        let migrated = sources()
        if migrated != stored { try saveSources(migrated) }
    }
    public func sourceDirectory(_ id: String) -> URL {
        // Only internal IDs are accepted, not arbitrary relative paths from an imported settings file.
        let safe = id.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        return sourceRoot.appendingPathComponent(safe.isEmpty ? "invalid" : safe, isDirectory: true)
    }
    public func activeSource(_ id: String) -> URL { sourceDirectory(id).appendingPathComponent("active", isDirectory: true) }
    public func privateFeeds() -> URL { root.appendingPathComponent("private-securiteinfo-urls.txt") }
    public var privateFeedsNeedConfiguration: Bool {
        if !FileManager.default.fileExists(atPath: privateFeeds().path) { return true }
        // Unreadable or malformed nonempty input is a real issue, not "empty".
        guard let text = try? String(contentsOf: privateFeeds()) else { return false }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    public func setPrivateFeeds(_ text: String) throws {
        let urls = try SourceManager.validateFeedURLs(text)
        try prepare()
        let data = Data(urls.map(\.absoluteString).joined(separator: "\n").utf8)
        try data.write(to: privateFeeds(), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privateFeeds().path)
        var values = sources()
        if let index = values.firstIndex(where: { $0.kind == .securiteinfo }) {
            // New account URLs are not validation of the previous downloaded DB.
            values[index].enabled = false
            values[index].updated = nil
            values[index].revision = nil
            values[index].files = 0
            values[index].lastError = nil
        }
        try saveSources(values)
    }
}

public struct SourceRefreshIssue: Identifiable {
    public var id: String
    public var name: String
    public var message: String
    public var description: String { "\(name): \(message)" }
}

public struct SourceManager {
    public var storage: Storage
    public init(storage: Storage = Storage()) { self.storage = storage }
    public func subscriptionURLs() throws -> [URL] {
        guard !storage.privateFeedsNeedConfiguration else {
            throw MarsError.message("No SecuriteInfo subscription URLs are configured. In Detection Sources, configure your own private feed URLs, update and validate the source, then enable it. ClamAV does not require this subscription.")
        }
        let text: String
        do { text = try String(contentsOf: storage.privateFeeds()) }
        catch { throw MarsError.message("The SecuriteInfo configuration cannot be read. Save your private feed URLs again in Detection Sources, or turn this optional source off.") }
        return try Self.validateFeedURLs(text)
    }
    public func setupIssue(for source: DetectionSource, requireActive: Bool) -> String? {
        if source.kind == .sanesecurity { return "Automatic Sanesecurity downloads have been removed. You can still import trusted definitions manually." }
        if source.kind == .securiteinfo && storage.privateFeedsNeedConfiguration {
            return "Not configured. Add your own private signature URLs, accept the provider terms, then update and validate to enable this optional source. ClamAV does not need a subscription."
        }
        if !source.acceptedTerms { return "Review and accept this provider's terms first. Acceptance does not enable the source." }
        // Configuration is checked before any private-file read, download, or engine work.
        if source.kind == .securiteinfo {
            do { _ = try subscriptionURLs() } catch { return error.localizedDescription }
        }
        if source.engine == .yaraX && !Engine.yaraXInstalled { return "Install YARA-X in Detection Sources before using this rule source." }
        if source.engine == .clamav && !Engine.installed { return "Install ClamAV before using this definition source." }
        if requireActive && (source.updated == nil || !FileManager.default.fileExists(atPath: storage.activeSource(source.id).path)) {
            return "Update & validate this source before enabling it. No validated active definitions are available."
        }
        return nil
    }
    public func acceptTerms(id: String) throws {
        let operationLock = try OperationLock(storage: storage)
        defer { withExtendedLifetime(operationLock) {} }
        var sources = storage.sources()
        guard let index = sources.firstIndex(where: { $0.id == id }) else { throw MarsError.message("Unknown source.") }
        sources[index].acceptedTerms = true
        // Consent and activation are different actions. In particular, a paid account is not
        // created merely by accepting its terms.
        sources[index].enabled = false
        try storage.saveSources(sources)
    }
    public func setEnabled(id: String, enabled: Bool) throws {
        let operationLock = try OperationLock(storage: storage)
        defer { withExtendedLifetime(operationLock) {} }
        var sources = storage.sources()
        guard let index = sources.firstIndex(where: { $0.id == id }) else { throw MarsError.message("Unknown source.") }
        if enabled, let issue = setupIssue(for: sources[index], requireActive: true) { throw MarsError.message(issue) }
        sources[index].enabled = enabled
        try storage.saveSources(sources)
    }
    /// Called while the caller holds the operation lock. One optional failure must not abort
    /// other sources or the baseline scan; cancellation, unlike a source failure, propagates.
    public func refreshOptionalUnlocked(_ requested: [DetectionSource], cancellation: Cancellation,
                                       line: (String) -> Void) throws -> [SourceRefreshIssue] {
        var issues: [SourceRefreshIssue] = []
        for source in requested where source.kind != .local {
            if cancellation.isCancelled { throw MarsError.message("Operation cancelled.") }
            do { try updateUnlocked(id: source.id, cancellation: cancellation, line: line) }
            catch {
                if cancellation.isCancelled { throw error }
                let issue = SourceRefreshIssue(id: source.id, name: source.name, message: error.localizedDescription)
                issues.append(issue)
                line("OPTIONAL SOURCE SKIPPED: \(issue.description)")
                line("The official ClamAV baseline remains available; this source will not be used in this scan.")
            }
        }
        return issues
    }
    public static func validateFeedURLs(_ text: String) throws -> [URL] {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty, lines.count <= 20 else { throw MarsError.message("Enter 1–20 signature download URLs from your own SecuriteInfo account.") }
        return try lines.map {
            guard let url = URL(string: $0), url.scheme == "https", url.host == "www.securiteinfo.com", url.port == nil || url.port == 443,
                  url.path.hasPrefix("/get/signatures/"), url.user == nil, url.password == nil,
                  !url.absoluteString.contains("\""), !url.absoluteString.contains("\\") else {
                throw MarsError.message("Only official HTTPS SecuriteInfo signature URLs are accepted. The invalid URL is not printed for privacy.")
            }
            return url
        }
    }
    public func validate(_ source: DetectionSource, directory: URL, cancellation: Cancellation, line: (String) -> Void) throws {
        if source.engine == .yaraX {
            guard let yr = Engine.executable("yr") else { throw MarsError.message("Install YARA-X before importing or updating its rules.") }
            let compiled = directory.deletingLastPathComponent().appendingPathComponent("validation-\(UUID()).yarc")
            defer { try? FileManager.default.removeItem(at: compiled) }
            let code = try ProcessRunner.run(yr, ["compile", directory.path, "--output", compiled.path], cancellation: cancellation, line: line)
            guard code == 0 else { throw MarsError.message("YARA-X could not compile this source. The previous rules remain active.") }
        } else {
            guard let clamscan = Engine.executable("clamscan") else { throw MarsError.message("Install ClamAV before importing its definitions.") }
            let fixture = directory.deletingLastPathComponent().appendingPathComponent("validation-\(UUID()).txt")
            try Data("Mars harmless source validation fixture, not malware.".utf8).write(to: fixture)
            defer { try? FileManager.default.removeItem(at: fixture) }
            let code = try ProcessRunner.run(clamscan, ["--database=\(directory.path)", "--stdout", "--", fixture.path], cancellation: cancellation, line: line)
            guard code == 0 else { throw MarsError.message("ClamAV rejected this database or it matched the harmless validation text. Previous definitions remain active.") }
        }
    }
    /// Runs under the shared operation lock. Directory rename is atomic on the same filesystem.
    public func promote(_ source: DetectionSource, staged: URL) throws {
        let fm = FileManager.default
        let parent = storage.sourceDirectory(source.id)
        let active = storage.activeSource(source.id), previous = parent.appendingPathComponent("previous")
        try? fm.removeItem(at: previous)
        if fm.fileExists(atPath: active.path) { try fm.moveItem(at: active, to: previous) }
        do { try fm.moveItem(at: staged, to: active) }
        catch { if fm.fileExists(atPath: previous.path) { try? fm.moveItem(at: previous, to: active) }; throw error }
    }
    public func rollback(id: String) throws {
        let operationLock = try OperationLock(storage: storage)
        defer { withExtendedLifetime(operationLock) {} }
        let fm = FileManager.default, parent = storage.sourceDirectory(id)
        let active = storage.activeSource(id), previous = parent.appendingPathComponent("previous"), temp = parent.appendingPathComponent("swap-\(UUID())")
        guard fm.fileExists(atPath: previous.path) else { throw MarsError.message("No previous validated version is available.") }
        try fm.moveItem(at: active, to: temp)
        do {
            try fm.moveItem(at: previous, to: active); try fm.moveItem(at: temp, to: previous)
        } catch { if !fm.fileExists(atPath: active.path) { try? fm.moveItem(at: temp, to: active) }; throw error }
        var sources = storage.sources()
        if let index = sources.firstIndex(where: { $0.id == id }) {
            sources[index].revision = "Rolled back; inspect local active files"
            sources[index].lastError = nil
            // No invented "last download" timestamp on rollback.
            try storage.saveSources(sources)
        }
    }
    public func importFiles(_ files: [URL], name: String, engine: DetectionEngine, cancellation: Cancellation, line: (String) -> Void) throws {
        let operationLock = try OperationLock(storage: storage)
        defer { withExtendedLifetime(operationLock) {} }
        var source = DetectionSource(id: "local-\(UUID().uuidString.lowercased())", name: name, engine: engine, kind: .local,
                                     license: "User confirms rights to these files", origin: "Local import; no automatic network update")
        source.acceptedTerms = true
        let stage = try staging(source)
        defer { try? FileManager.default.removeItem(at: stage) }
        guard !files.isEmpty, files.count <= 200 else { throw MarsError.message("Select 1–200 definition or rule files.") }
        let allowed = engine == .yaraX ? ["yar", "yara"] : ["yar", "yara", "ndb", "ldb", "hdb", "hsb", "mdb", "msb", "sdb", "cdb", "fp", "sfp", "ign", "ign2"]
        var names = Set<String>()
        for file in files {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) <= 100 * 1024 * 1024,
                  allowed.contains(file.pathExtension.lowercased()), names.insert(file.lastPathComponent).inserted else {
                throw MarsError.message("Import rejected: duplicate names, symlinks, oversized files, or unsupported format. Bytecode and executable updates are not accepted.")
            }
            if ["yar", "yara"].contains(file.pathExtension.lowercased()) {
                let text = try String(contentsOf: file)
                // Includes can read unrelated local paths at compilation time. Require standalone packs.
                if text.range(of: #"\binclude\b"#, options: .regularExpression) != nil {
                    throw MarsError.message("Imported YARA containing the include keyword is not allowed, even inside comments or strings. Use a trusted self-contained pack; rules must not open unrelated files at compilation time.")
                }
            }
            try FileManager.default.copyItem(at: file, to: stage.appendingPathComponent(file.lastPathComponent))
        }
        try validate(source, directory: stage, cancellation: cancellation, line: line)
        try promote(source, staged: stage)
        source.enabled = true; source.updated = Date(); source.files = files.count; source.revision = "Validated local import"
        var sources = storage.sources(); sources.append(source); try storage.saveSources(sources)
    }
    private func staging(_ source: DetectionSource) throws -> URL {
        try storage.prepare()
        let parent = storage.sourceDirectory(source.id)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let stage = parent.appendingPathComponent("staging-\(UUID())")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        return stage
    }
    /// curl is used as a bounded, cancellable transport; content still needs pinned hash/GPG or licensed-feed validation.
    private func download(_ url: URL, destination: URL, cancellation: Cancellation) throws {
        guard url.scheme == "https" else { throw MarsError.message("Insecure download rejected.") }
        let config = destination.deletingLastPathComponent().appendingPathComponent("transport-\(UUID()).conf")
        let escaped = url.absoluteString.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        try Data("url = \"\(escaped)\"\n".utf8).write(to: config, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
        defer { try? FileManager.default.removeItem(at: config) }
        let code = try ProcessRunner.run("/usr/bin/curl", ["--fail", "--silent", "--show-error", "--location",
            "--proto", "=https", "--proto-redir", "=https", "--max-time", "180", "--max-filesize", "104857600",
            "--output", destination.path, "--config", config.path], cancellation: cancellation)
        guard code == 0 else { throw MarsError.message("Source download failed (transport \(code)). No private URL is included in this error.") }
    }
    public func update(id: String, cancellation: Cancellation, line: (String) -> Void) throws {
        let operationLock = try OperationLock(storage: storage)
        defer { withExtendedLifetime(operationLock) {} }
        try updateUnlocked(id: id, cancellation: cancellation, line: line)
    }
    public func updateUnlocked(id: String, cancellation: Cancellation, line: (String) -> Void) throws {
        var sources = storage.sources()
        guard let index = sources.firstIndex(where: { $0.id == id }) else { throw MarsError.message("Unknown detection source.") }
        var source = sources[index]
        if let issue = setupIssue(for: source, requireActive: false) {
            sources[index].lastError = issue
            try storage.saveSources(sources)
            throw MarsError.message(issue)
        }
        guard source.kind != .local else { line("\(source.name): local import; no automatic updater."); return }
        let stage = try staging(source)
        defer { try? FileManager.default.removeItem(at: stage) }
        do {
            line("Preparing \(source.name). The active copy stays untouched until validation succeeds.")
            switch source.kind {
            case .elastic:
                for (file, hash) in Catalog.elasticFiles {
                    let target = stage.appendingPathComponent(file)
                    let url = URL(string: "https://raw.githubusercontent.com/elastic/protections-artifacts/\(Catalog.elasticRevision)/yara/rules/\(file)")!
                    try download(url, destination: target, cancellation: cancellation)
                    try Catalog.check(Data(contentsOf: target), expected: hash)
                }
                let license = stage.appendingPathComponent("LICENSE.txt")
                try download(URL(string: "https://raw.githubusercontent.com/elastic/protections-artifacts/\(Catalog.elasticRevision)/LICENSE.txt")!, destination: license, cancellation: cancellation)
                try Catalog.check(Data(contentsOf: license), expected: "48255018b41fc0e965b1115af7e6779bc218bb8a6747d561da800d5022622aa2")
                source.files = Catalog.elasticFiles.count; source.revision = Catalog.elasticRevision
            case .sanesecurity:
                throw MarsError.message("Automatic Sanesecurity downloads have been removed. Import trusted definitions manually instead.")
            case .securiteinfo:
                let urls = try subscriptionURLs()
                for (offset, url) in urls.enumerated() {
                    let ext = url.pathExtension.lowercased()
                    guard ["ndb", "ldb", "hdb", "hsb", "cvd", "cld", "ign2", "fp", "sfp"].contains(ext) else { throw MarsError.message("Unsupported subscription database format.") }
                    try download(url, destination: stage.appendingPathComponent("feed-\(offset).\(ext)"), cancellation: cancellation)
                }
                source.files = urls.count; source.revision = "Own subscription; HTTPS transport, engine validation"
            case .local: break
            }
            try validate(source, directory: stage, cancellation: cancellation, line: line)
            guard !cancellation.isCancelled else { throw MarsError.message("Cancelled before source activation.") }
            try promote(source, staged: stage)
            source.updated = Date(); source.lastError = nil
            sources[index] = source; try storage.saveSources(sources)
            line("\(source.name): validated and activated. Previous copy retained for rollback.")
        } catch {
            sources[index].lastError = error.localizedDescription
            try? storage.saveSources(sources)
            throw error
        }
    }
}
