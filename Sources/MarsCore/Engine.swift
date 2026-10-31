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
        var arguments = ["--database=\(database.path)", "--recursive=yes", "--infected", "--stdout",
                         "--follow-dir-symlinks=0", "--follow-file-symlinks=0", "--alert-exceeds-max=yes"]
        if fullMac {
            // Exclude external volumes and virtual/runtime mounts, not the writable Data volume.
            arguments += ["--exclude-dir=^(/System/Volumes/Data)?/Volumes(/|$)", "--exclude-dir=^/dev(/|$)",
                          "--exclude-dir=^/System/Volumes/(Preboot|VM|Update|xarts|iSCPreboot|Hardware)(/|$)"]
        }
        return arguments + ["--"] + targets
    }
    public func scan(preferences: Preferences, scheduled: Bool = false, cancellation: Cancellation,
                     line: (String) -> Void) throws -> ScanRecord {
        let operationLock = try OperationLock(storage: storage)
        defer { withExtendedLifetime(operationLock) {} }
        let targets = try Self.targets(for: preferences)
        guard let clamscan = Self.executable("clamscan") else { throw MarsError.message("Install ClamAV first.") }
        var record = ScanRecord(scope: preferences.scope, targets: targets)
        record.scheduled = scheduled
        record.logPath = storage.logs.appendingPathComponent("\(record.id.uuidString).log").path
        do {
            if preferences.updateBeforeScan {
                line("Updating definitions before scanning…")
                try updateUnlocked(cancellation: cancellation, line: line)
            }
            guard storage.hasDefinitions else { throw MarsError.message("Download definitions before your first scan.") }
            line("Scanning \(targets.joined(separator: ", "))")
            line("ClamAV is loading its database. This can take a minute; the scan has no reliable percentage.")
            var parser = ScanParser()
            let code = try ProcessRunner.run(clamscan,
                Self.scanArguments(database: storage.database, targets: targets, fullMac: preferences.scope == .mac),
                cancellation: cancellation, log: URL(fileURLWithPath: record.logPath)) { text in
                    parser.consume(text); line(text)
                }
            record.exitCode = code
            record.findings = parser.findings
            record.scannedFiles = parser.scannedFiles
            record.warnings = parser.warnings
            record.outcome = parser.outcome(exitCode: code, cancelled: cancellation.isCancelled)
            record.note = parser.scannedFiles == 0
                ? "No files were inspected. The location may be empty, inaccessible, or excluded. No files were changed."
                : "Only accessible files within ClamAV's engine limits were scanned. No files were changed."
        } catch {
            record.outcome = cancellation.isCancelled ? .cancelled : .failed
            record.note = error.localizedDescription
            line(record.note)
        }
        record.finished = Date()
        try storage.save(record)
        return record
    }
}
