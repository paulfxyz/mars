import Foundation

public final class Cancellation {
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false
    public init() {}
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    public func attach(_ value: Process) {
        lock.lock(); process = value; let shouldStop = stopped; lock.unlock()
        if shouldStop && value.isRunning { value.terminate() }
    }
    public func cancel() {
        lock.lock(); stopped = true; let running = process; lock.unlock()
        if let running, running.isRunning { running.terminate() }
    }
}

public enum ProcessRunner {
    @discardableResult
    public static func run(_ executable: String, _ arguments: [String], cancellation: Cancellation = Cancellation(),
                           log: URL? = nil, line: (String) -> Void = { _ in }) throws -> Int32 {
        if cancellation.isCancelled { throw MarsError.message("Operation cancelled.") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["LC_ALL"] = "C"
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        var output: FileHandle?
        if let log {
            FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
            output = try FileHandle(forWritingTo: log)
        }
        defer { try? output?.close() }
        try process.run()
        cancellation.attach(process)
        var pending = Data()
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            // Bound each raw log to 32 MiB. Parsing and live output continue after this limit.
            if let output, ((try? output.offset()) ?? 0) < 32 * 1024 * 1024 { try? output.write(contentsOf: chunk) }
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 10) {
                let data = pending[..<newline]
                line(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines))
                pending.removeSubrange(...newline)
            }
            if pending.count > 256 * 1024 {
                line(String(decoding: pending, as: UTF8.self)); pending.removeAll(keepingCapacity: true)
            }
        }
        if !pending.isEmpty { line(String(decoding: pending, as: UTF8.self)) }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

public struct Engine {
    public let storage: Storage
    public init(storage: Storage = Storage()) { self.storage = storage }
    public static func executable(_ name: String) -> String? {
        let candidates = ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)",
                          "/opt/homebrew/opt/clamav/bin/\(name)", "/usr/local/opt/clamav/bin/\(name)"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    public static var installed: Bool { executable("clamscan") != nil && executable("freshclam") != nil }
    public static var yaraXInstalled: Bool { executable("yr") != nil }
    public static var brew: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    public func install(cancellation: Cancellation, line: (String) -> Void) throws {
        let operationLock = try OperationLock(storage: storage)
        defer { withExtendedLifetime(operationLock) {} }
        guard let brew = Self.brew else { throw MarsError.message("Install Homebrew first, then return to mars.") }
        let code = try ProcessRunner.run(brew, ["install", "clamav"], cancellation: cancellation,
            log: storage.logs.appendingPathComponent("install.log"), line: line)
        guard code == 0 && Self.installed else { throw MarsError.message("ClamAV installation did not finish. Review the activity log and try again.") }
    }
    public func update(cancellation: Cancellation, line: (String) -> Void) throws {
        let operationLock = try OperationLock(storage: storage)
        defer { withExtendedLifetime(operationLock) {} }
        try updateUnlocked(cancellation: cancellation, line: line)
        for source in storage.sources().filter(\.enabled) where source.kind != .local {
            try SourceManager(storage: storage).updateUnlocked(id: source.id, cancellation: cancellation, line: line)
        }
    }
    public func installOptional(package: String, cancellation: Cancellation, line: (String) -> Void) throws {
        guard ["yara-x", "gnupg"].contains(package), let brew = Self.brew else { throw MarsError.message("Homebrew is required for this optional component.") }
        let operationLock = try OperationLock(storage: storage)
        defer { withExtendedLifetime(operationLock) {} }
        let code = try ProcessRunner.run(brew, ["install", package], cancellation: cancellation, line: line)
        guard code == 0 else { throw MarsError.message("Optional component installation did not finish. Check the console. On older macOS or Intel, Homebrew may need to build from source or may not support the current formula.") }
    }
    private func updateUnlocked(cancellation: Cancellation, line: (String) -> Void) throws {
        guard let freshclam = Self.executable("freshclam") else { throw MarsError.message("Install ClamAV before updating definitions.") }
        try storage.writeFreshclamConfig()
        let code = try ProcessRunner.run(freshclam, ["--config-file=\(storage.config.path)", "--stdout"],
            cancellation: cancellation, log: storage.logs.appendingPathComponent("definitions.log"), line: line)
        guard code == 0 && storage.hasDefinitions else {
            throw MarsError.message("Definitions could not be updated (exit \(code)). The mirror may be rate-limiting requests; check the log before retrying.")
        }
    }
    public static func targets(for preferences: Preferences) throws -> [String] {
        switch preferences.scope {
        case .mac: return ["/"]
        case .home: return [FileManager.default.homeDirectoryForCurrentUser.path]
        case .folders:
            let paths = Array(Set(preferences.folders)).sorted()
            guard !paths.isEmpty else { throw MarsError.message("Choose at least one folder to scan.") }
            for path in paths {
                var directory: ObjCBool = false
                guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue else {
                    throw MarsError.message("Folder is missing or unavailable: \(path)")
                }
            }
            return paths
        }
    }
    public static func scanArguments(database: URL, targets: [String], fullMac: Bool) -> [String] {
        var arguments = ["--database=\(database.path)", "--recursive=yes", "--verbose", "--stdout",
                         "--follow-dir-symlinks=0", "--follow-file-symlinks=0", "--alert-exceeds-max=yes"]
        if fullMac {
            // Exclude external volumes and virtual/runtime mounts, not the writable Data volume.
            arguments += ["--exclude-dir=^(/System/Volumes/Data)?/Volumes(/|$)", "--exclude-dir=^/dev(/|$)", "--exclude-dir=^/Network(/|$)",
                          "--exclude-dir=^/System/Volumes/(Preboot|VM|Update|xarts|iSCPreboot|Hardware)(/|$)"]
        }
        return arguments + ["--"] + targets
    }
    public func scan(preferences: Preferences, scheduled: Bool = false, cancellation: Cancellation,
                     progress: (ScanUpdate) -> Void = { _ in }, line: (String) -> Void) throws -> ScanRecord {
        let operationLock = try OperationLock(storage: storage)
        defer { withExtendedLifetime(operationLock) {} }
        let targets = try Self.targets(for: preferences)
        guard let clamscan = Self.executable("clamscan") else { throw MarsError.message("Install ClamAV first.") }
        var record = ScanRecord(scope: preferences.scope, targets: targets)
        record.passes = []; record.coverageNotes = []
        record.scheduled = scheduled
        record.logPath = storage.logs.appendingPathComponent("\(record.id.uuidString).log").path
        do {
            let sources = storage.sources().filter(\.enabled)
            let yaraEnabled = preferences.yaraXEnabled == true
            let requested = sources.filter { $0.engine == .clamav || yaraEnabled }
            let missingYaraSource = yaraEnabled && !requested.contains(where: { $0.engine == .yaraX })
            let total = 1 + requested.count + (missingYaraSource ? 1 : 0)
            progress(ScanUpdate(stage: "Preparing your scan", explanation: "Checking the selected folders, engines, and sources. Nothing on your Mac will be changed.", totalPasses: total))
            if preferences.updateBeforeScan {
                progress(ScanUpdate(stage: "Refreshing detection sources", explanation: "Downloading and validating updates before looking at your files.", totalPasses: total))
                line("Updating definitions before scanning…")
                try updateUnlocked(cancellation: cancellation, line: line)
                for source in requested where source.kind != .local {
                    try SourceManager(storage: storage).updateUnlocked(id: source.id, cancellation: cancellation, line: line)
                }
            }
            guard storage.hasDefinitions else { throw MarsError.message("Download definitions before your first scan.") }
            line("Scanning \(targets.joined(separator: ", "))")
            line("[ClamAV / Official ClamAV] Starting baseline inspection.")
            line("ClamAV is loading its database. This can take a minute; the scan has no reliable percentage.")
            var parser = ScanParser()
            var observed = 0
            var lastTick = Date.distantPast
            progress(ScanUpdate(stage: "ClamAV is checking your files", explanation: "ClamAV loads its database, then inspects files and supported archive contents. A reliable percentage is not available.",
                                source: "Official ClamAV", totalPasses: total))
            let code = try ProcessRunner.run(clamscan,
                Self.scanArguments(database: storage.database, targets: targets, fullMac: preferences.scope == .mac),
                cancellation: cancellation, log: URL(fileURLWithPath: record.logPath)) { text in
                    parser.consume(text); line(text)
                    if text.hasSuffix(": OK") || text.hasSuffix(" FOUND") || text.hasSuffix(" ERROR") { observed += 1 }
                    if Date().timeIntervalSince(lastTick) > 0.25 {
                        progress(ScanUpdate(stage: "ClamAV is checking your files", explanation: "Leave Mars running; you can stop safely at any time.",
                            source: "Official ClamAV", totalPasses: total, observedFiles: observed, findings: parser.findings.count,
                            currentPath: text.hasSuffix(": OK") ? String(text.dropLast(4)) : ""))
                        lastTick = Date()
                    }
                }
            record.exitCode = code
            record.findings = parser.findings.map { value in
                var finding = value; finding.engine = "ClamAV"; finding.source = "Official ClamAV"; return finding
            }
            record.scannedFiles = parser.scannedFiles
            record.warnings = parser.warnings
            record.outcome = parser.outcome(exitCode: code, cancelled: cancellation.isCancelled)
            record.passes?.append(ScanPass(engine: "ClamAV", source: "Official ClamAV", status: record.outcome.rawValue,
                files: parser.scannedFiles, findings: parser.findings.count, warnings: parser.warnings, logPath: record.logPath))
            var completed = 1
            var plan: YaraPlan?
            defer { if let plan { try? FileManager.default.removeItem(at: plan.list) } }
            for source in requested {
                if cancellation.isCancelled { break }
                line("[\(source.engine.rawValue) / \(source.name)] Starting this source's inspection.")
                let active = storage.activeSource(source.id)
                let logURL = storage.logs.appendingPathComponent("\(record.id.uuidString)-\(source.id).log")
                progress(ScanUpdate(stage: "\(source.engine.rawValue) · \(source.name)", explanation: "Checking this source separately so every match has clear provenance.",
                    source: source.name, completedPasses: completed, totalPasses: total, findings: record.findings.count))
                guard source.updated != nil, FileManager.default.fileExists(atPath: active.path) else {
                    record.passes?.append(ScanPass(engine: source.engine.rawValue, source: source.name, status: "notRun", warnings: 1))
                    record.coverageNotes?.append("\(source.name) was enabled but has no validated active files. Configure and update it, or disable it.")
                    record.warnings += 1; completed += 1; continue
                }
                if source.engine == .clamav {
                    var extra = ScanParser()
                    let result = try ProcessRunner.run(clamscan, Self.scanArguments(database: active, targets: targets, fullMac: preferences.scope == .mac),
                        cancellation: cancellation, log: logURL) { text in extra.consume(text); line(text) }
                    for var finding in extra.findings { finding.engine = "ClamAV"; finding.source = source.name; record.findings.append(finding) }
                    let outcome = extra.outcome(exitCode: result, cancelled: cancellation.isCancelled)
                    record.passes?.append(ScanPass(engine: "ClamAV", source: source.name, status: outcome.rawValue, files: extra.scannedFiles,
                        findings: extra.findings.count, warnings: extra.warnings, logPath: logURL.path))
                    record.warnings += extra.warnings + ([.failed, .incomplete].contains(outcome) ? 1 : 0)
                } else {
                    guard let yr = Self.executable("yr") else {
                        record.passes?.append(ScanPass(engine: "YARA-X", source: source.name, status: "notRun", warnings: 1))
                        record.coverageNotes?.append("YARA-X is enabled but not installed. ClamAV results are still available.")
                        record.warnings += 1; completed += 1; continue
                    }
                    if plan == nil {
                        progress(ScanUpdate(stage: "Preparing the YARA-X file list", explanation: "Selecting accessible raw files within the explicit 32 MiB and 500,000-file limits.",
                            completedPasses: completed, totalPasses: total))
                        plan = try YaraPlan.build(targets: targets, fullMac: preferences.scope == .mac, storage: storage, cancellation: cancellation) { count, path in
                            progress(ScanUpdate(stage: "Preparing the YARA-X file list", explanation: "\(count.formatted()) candidate files selected. This is preparation, not a count of scanned files.",
                                completedPasses: completed, totalPasses: total, currentPath: path))
                        }
                        record.coverageNotes?.append(contentsOf: plan!.notes)
                        record.warnings += (plan!.skipped > 0 ? 1 : 0) + plan!.issues
                    }
                    progress(ScanUpdate(stage: "YARA-X is checking raw files", explanation: "\(plan!.candidates.formatted()) candidate files submitted to this rule pack. Candidate count is not a confirmed inspection count. Archive members are not unpacked by this engine.",
                        source: source.name, completedPasses: completed, totalPasses: total, findings: record.findings.count))
                    var extra = YaraParser()
                    let result = try ProcessRunner.run(yr, ["scan", "--output-format", "ndjson", "--disable-console-logs", "--threads", "2",
                        "--timeout", "3600", "--scan-list", active.path, plan!.list.path], cancellation: cancellation, log: logURL) { text in
                            extra.consume(text, source: source.name); line(text)
                        }
                    record.findings += extra.findings
                    let partial = result != 0 || extra.warnings > 0 || plan!.candidates == 0
                    record.passes?.append(ScanPass(engine: "YARA-X", source: source.name, status: partial ? "incomplete" : "completed",
                        files: plan!.candidates, findings: extra.findings.count, warnings: extra.warnings + (partial ? 1 : 0), logPath: logURL.path,
                        countMeaning: "candidate files submitted; not independently confirmed"))
                    record.warnings += extra.warnings + (partial ? 1 : 0)
                }
                completed += 1
            }
            if missingYaraSource {
                record.coverageNotes?.append("YARA-X was requested but no YARA-X source is enabled. No second-engine check ran.")
                record.passes?.append(ScanPass(engine: "YARA-X", source: "No rules enabled", status: "notRun", warnings: 1))
                record.warnings += 1
            }
            if cancellation.isCancelled { record.outcome = .cancelled }
            else if !record.findings.isEmpty { record.outcome = .threatsFound }
            else if record.warnings > 0 { record.outcome = .incomplete }
            record.note = parser.scannedFiles == 0
                ? "No files were inspected. The location may be empty, inaccessible, or excluded. No files were changed."
                : "The headline file count is ClamAV's baseline count, not a sum of repeated source checks. Only accessible files within each engine's limits were checked. No files were changed."
        } catch {
            record.outcome = cancellation.isCancelled ? .cancelled : .failed
            record.note = error.localizedDescription
            line(record.note)
        }
        record.finished = Date()
        progress(ScanUpdate(stage: "Writing your report", explanation: "Saving source-by-source results and coverage notes locally. Your files were not changed."))
        try storage.save(record)
        return record
    }
}
