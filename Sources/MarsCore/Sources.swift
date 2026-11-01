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
        case .sanesecurity: return "Malware hashes (rogue and malwarehash) plus required file-type and false-positive allowlist files. Downloads use rsync and must pass verification against the pinned provider key. Signed payload dates are shown separately from download time."
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
            DetectionSource(id: "sanesecurity", name: "Sanesecurity malware hashes", engine: .clamav, kind: .sanesecurity,
                            license: "Provider terms; review before enabling", origin: "https://sanesecurity.com/usage/signatures/"),
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
        return stored + Catalog.defaults.filter { base in !stored.contains { $0.id == base.id } }
    }
    public func saveSources(_ sources: [DetectionSource]) throws {
        try prepare()
        try JSONEncoder().encode(sources).write(to: sourceSettings, options: .atomic)
    }
    public func sourceDirectory(_ id: String) -> URL {
        // Only internal IDs are accepted, not arbitrary relative paths from an imported settings file.
        let safe = id.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        return sourceRoot.appendingPathComponent(safe.isEmpty ? "invalid" : safe, isDirectory: true)
    }
    public func activeSource(_ id: String) -> URL { sourceDirectory(id).appendingPathComponent("active", isDirectory: true) }
    public func privateFeeds() -> URL { root.appendingPathComponent("private-securiteinfo-urls.txt") }
    public func setPrivateFeeds(_ text: String) throws {
        let urls = try SourceManager.validateFeedURLs(text)
        try prepare()
        let data = Data(urls.map(\.absoluteString).joined(separator: "\n").utf8)
        try data.write(to: privateFeeds(), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privateFeeds().path)
    }
}

public struct SourceManager {
    public var storage: Storage
    public init(storage: Storage = Storage()) { self.storage = storage }
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
        guard source.acceptedTerms else { throw MarsError.message("Review and accept this source's separate terms first.") }
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
                let dates = try downloadSanesecurity(stage: stage, cancellation: cancellation, line: line)
                source.files = 4; source.revision = "GPG verified; signed payload dates: \(dates.joined(separator: " · ")). Download time does not establish freshness."
            case .securiteinfo:
                let raw = try String(contentsOf: storage.privateFeeds())
                let urls = try Self.validateFeedURLs(raw)
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
    private func downloadSanesecurity(stage: URL, cancellation: Cancellation, line: (String) -> Void) throws -> [String] {
        guard let gpg = Engine.executable("gpg") else { throw MarsError.message("Sanesecurity requires GnuPG. Use Install verification tools in Detection Sources.") }
        let home = stage.deletingLastPathComponent().appendingPathComponent("gpg-\(UUID())")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: home) }
        let key = home.appendingPathComponent("vendor.asc")
        try Data(Self.sanesecurityKey.utf8).write(to: key)
        let ring = home.appendingPathComponent("vendor.gpg")
        guard try ProcessRunner.run(gpg, ["--no-options", "--homedir", home.path, "--batch", "--dearmor", "--output", ring.path, key.path], cancellation: cancellation) == 0 else {
            throw MarsError.message("Could not load the pinned Sanesecurity verification key.")
        }
        var dates: [String] = []
        for file in ["rogue.hdb", "malwarehash.hsb", "sigwhitelist.ign2", "sanesecurity.ftm"] {
            for name in [file, "\(file).sig"] {
                var details: [String] = []
                // macOS's built-in rsync can be 2.6.x; --contimeout is not supported there.
                let code = try ProcessRunner.run(Engine.executable("rsync") ?? "/usr/bin/rsync", ["--timeout=30", "--max-size=100000000",
                    "rsync://rsync.sanesecurity.net/sanesecurity/\(name)", stage.appendingPathComponent(name).path], cancellation: cancellation) { details.append($0) }
                guard code == 0 else { throw MarsError.message("Sanesecurity transport failed (exit \(code)): \(details.suffix(3).joined(separator: " ")). Previous signatures remain unchanged.") }
            }
            var verified = false
            var signedDate = "date not reported"
            let code = try ProcessRunner.run(gpg, ["--no-options", "--homedir", home.path, "--batch", "--no-default-keyring",
                "--keyring", ring.path, "--trust-model", "always", "--no-auto-key-retrieve", "--no-autostart",
                "--status-fd", "1", "--verify", stage.appendingPathComponent("\(file).sig").path,
                stage.appendingPathComponent(file).path], cancellation: cancellation) { text in
                    if text.contains("[GNUPG:] VALIDSIG ") {
                        verified = true
                        let fields = text.split(separator: " ")
                        if fields.count > 3 { signedDate = String(fields[3]) }
                    }
                }
            guard code == 0 && verified else { throw MarsError.message("Sanesecurity GPG verification failed. Nothing was activated.") }
            try FileManager.default.removeItem(at: stage.appendingPathComponent("\(file).sig"))
            dates.append("\(file): \(signedDate)")
            line("Verified \(file) against the pinned provider key; payload signed \(signedDate).")
        }
        return dates
    }
    static let sanesecurityKey = """
    -----BEGIN PGP PUBLIC KEY BLOCK-----
    Version: GnuPG v1.4.9 (MingW32)

    mQGiBElnAKcRBACX5ELfVPeAubJaQDQZHF8fGZFVkmT54J2uj0UwLfxbN5dQ4jEr
    Pxdr0UiqOA0cttKpe0m6IZHnkbeeY4s0/HpaVZKGXsiizazB4F2NdzskuT4TRGXg
    fAMQ16mlpslY//quEfIQzTSKPhEKpVHqZTn8wjSDZQo+NI3qmBODz9p5HwCggFoi
    p2/LpvjmLkjPFKNpyjOwt6sD/ifFA07EmF9vxOG7aXqB7Z5zB24rpXb3/KBPbF93
    6bvbT70jlwMczdOt9eNK7brpIj/ZpkdUol84MYb7sv9ZC3+qmVFKERo1rM+kvkXV
    jjCFBRMyBTYYB67RgkMd79gaJ3Zo9SavQW65EtFxMr5aDfbXwkshoI3EzwVSsVPv
    MoQwA/40qOV6eXQChLet795btwhbmVWvrAZ7MaN8Gdx0hMP+a9DOGo0O4J1GeNXX
    Prt9PLdmUb2cahqrIVDVis6KDjD3GSdgRPf8zZ6kDUteeMND4EsYytpOQl8AeL6h
    9zncFtPng1Kj/aAJyxO38YvPMFLkQV/iyZu/0Oq8RIFp/E1ZG7RJU2FuZXNlY3Vy
    aXR5IChTYW5lc2VjdXJpdHkgU2lnbmF0dXJlcykgPHN0ZXZlYl9jbGFtYXZAc2Fu
    ZXNlY3VyaXR5LmNvLnVrPohgBBMRAgAgBQJJZwCnAhsDBgsJCAcDAgQVAggDBBYC
    AwECHgECF4AACgkQ1pHe2THqTZ7mowCaA9QGSxkN6XP7dbOlrjB9aDp5D90AniNm
    W0NT6DUEVRMLnvWvnnlfufsJuQINBElnAKcQCAC1/hC7vENr66EkX0t8FAtKKZ31
    kMYYjUd24uXYBEL/Fwip+JDpS9xUClK70PVcJ/Ad0z4lYQRUgRcCvq5twF5clmMG
    E7M+K5vgJtjk2Wvl+w77X6za9bu8euwkzzWeyskmUpJ78EAcwsOk28Q8VPtrI76z
    JjLqdY3tFXkCwCLvKzfhdg+3967B4ge+XBdTCQhE6dQ+A5ePMQKZj365A8BQdHOY
    +e/MuGH6LbB/VuqGD7kjC+gE44syY/O6X9STRufvCYwPlqkJVpuR2arFIIGcXzP0
    GA4m8ESFY5N68QXYvzO60CqGABhFEmAtGul7ZOJgI8QLcVIPn+lghL8V9IYDAAMG
    B/4zh/khzx4TwkiAU40nsCvgjVeNKF0frka/AXdODzf9MDyJEdrdxFSKNANS/IPJ
    W/n0gk5khwOcNnCIAM/GMm5szJftywhmuM3vXM6l+pHLF1/FABpNCFzjQAsBDg+g
    dIYFhE9qDbFf1ZBGuJp0fdUyKG9fkdkYX4tN0F2bM6hqAIZab1FfDQC/rRcFmA0t
    MeQwAQCOsyva3ipRa0xoAWS8C5bpXeVZbo9ZAGw/W+MDi7atrqURB0HRKB9PZB1J
    BLlaQgZAHILykpQEE2gelUwihZS9MadB2bEvrJcbhgxaRqarAam/rcTLrMEOWgdP
    uPNmK1GeJrr7D6H1g5TSYYKoiEkEGBECAAkFAklnAKcCGwwACgkQ1pHe2THqTZ6C
    vACdF31uNpoParageOrmdtOdJUKUs0cAn2DLySqry2A5FlQ/6W+7IptN02IE
    =fh8i
    -----END PGP PUBLIC KEY BLOCK-----
    """
}
