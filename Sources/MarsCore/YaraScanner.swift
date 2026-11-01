import Foundation

public struct YaraParser {
    public private(set) var findings: [Finding] = []
    public private(set) var warnings = 0
    public init() {}
    public mutating func consume(_ line: String, source: String) {
        if let data = line.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let path = object["path"] as? String,
           let rules = object["rules"] as? [[String: Any]] {
            for rule in rules {
                guard let identifier = rule["identifier"] as? String else { continue }
                var finding = Finding(path: path, signature: identifier)
                finding.engine = DetectionEngine.yaraX.rawValue; finding.source = source
                finding.assessment = "YARA rule match; pattern evidence, not confirmation of infection"
                findings.append(finding)
            }
        } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
            // Non-JSON diagnostics must not disappear, including file errors on a zero exit code.
            warnings += 1
        }
    }
}

public struct YaraPlan {
    public var list: URL
    public var candidates: Int
    public var skipped: Int
    public var issues: Int
    public var notes: [String]
    public static let sizeLimit = 32 * 1024 * 1024
    public static let fileLimit = 500_000
    public static func excluded(_ path: String, fullMac: Bool) -> Bool {
        guard fullMac else { return false }
        return ["/Volumes", "/System/Volumes/Data/Volumes", "/dev", "/Network",
                "/System/Volumes/Preboot", "/System/Volumes/VM", "/System/Volumes/Update", "/System/Volumes/xarts",
                "/System/Volumes/iSCPreboot", "/System/Volumes/Hardware"].contains { path == $0 || path.hasPrefix($0 + "/") }
    }
    public static func build(targets: [String], fullMac: Bool, storage: Storage, cancellation: Cancellation,
                             progress: (Int, String) -> Void) throws -> YaraPlan {
        let fm = FileManager.default
        let list = storage.root.appendingPathComponent("yara-targets-\(UUID()).txt")
        fm.createFile(atPath: list.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let output = try FileHandle(forWritingTo: list)
        var plan = YaraPlan(list: list, candidates: 0, skipped: 0, issues: 0, notes: [])
        var succeeded = false
        defer { try? output.close(); if !succeeded { try? fm.removeItem(at: list) } }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey]
        // Remove nested scopes so a selected parent and child do not duplicate this engine's file list.
        let roots = targets.sorted { $0.count < $1.count }.reduce(into: [String]()) { roots, path in
            if !roots.contains(where: { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }) { roots.append(path) }
        }
        outer: for target in roots {
            guard let enumerator = fm.enumerator(at: URL(fileURLWithPath: target), includingPropertiesForKeys: Array(keys), options: [],
                errorHandler: { _, _ in plan.issues += 1; return true }) else { plan.issues += 1; continue }
            for case let file as URL in enumerator {
                if cancellation.isCancelled { throw MarsError.message("Operation cancelled.") }
                if excluded(file.path, fullMac: fullMac) { enumerator.skipDescendants(); continue }
                do {
                    let values = try file.resourceValues(forKeys: keys)
                    if values.isSymbolicLink == true { enumerator.skipDescendants(); plan.skipped += 1; continue }
                    guard values.isRegularFile == true else { continue }
                    guard (values.fileSize ?? 0) <= sizeLimit, !file.path.contains("\n"), !file.path.contains("\r") else { plan.skipped += 1; continue }
                    guard plan.candidates < fileLimit else { plan.issues += 1; plan.notes.append("YARA-X stopped enumerating at the 500,000-file safety limit."); break outer }
                    try output.write(contentsOf: Data((file.path + "\n").utf8))
                    plan.candidates += 1
                    if plan.candidates % 250 == 0 { progress(plan.candidates, file.path) }
                } catch { plan.issues += 1 }
            }
        }
        plan.notes.append("YARA-X examines raw file bytes, not unpacked archive members. Files above 32 MiB, symlinks, and newline-containing paths are not submitted.")
        if plan.skipped > 0 { plan.notes.append("YARA-X skipped \(plan.skipped) entries because of its explicit file/path limits.") }
        if plan.issues > 0 { plan.notes.append("YARA-X encountered \(plan.issues) enumeration or access issues.") }
        succeeded = true
        return plan
    }
}
