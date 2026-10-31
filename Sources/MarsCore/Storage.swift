import Foundation
import Darwin

public struct Storage {
    public let root: URL
    public var database: URL { root.appendingPathComponent("Database", isDirectory: true) }
    public var logs: URL { root.appendingPathComponent("Logs", isDirectory: true) }
    public var records: URL { root.appendingPathComponent("History", isDirectory: true) }
    public var preferencesURL: URL { root.appendingPathComponent("preferences.json") }
    public var config: URL { root.appendingPathComponent("freshclam.conf") }

    public init(root: URL? = nil) {
        self.root = root ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/mars", isDirectory: true)
    }
    public func prepare() throws {
        for directory in [root, database, logs, records] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        }
    }
    public func preferences() -> Preferences {
        guard let data = try? Data(contentsOf: preferencesURL),
              let value = try? JSONDecoder().decode(Preferences.self, from: data) else { return Preferences() }
        return value
    }
    public func save(_ value: Preferences) throws {
        try prepare()
        try JSONEncoder().encode(value).write(to: preferencesURL, options: .atomic)
    }
    public func save(_ record: ScanRecord) throws {
        try prepare()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: records.appendingPathComponent("\(record.id.uuidString).json"), options: .atomic)
        // Bound local history and remove only logs referenced by expired records.
        let old = history().dropFirst(200)
        for entry in old {
            try? FileManager.default.removeItem(at: records.appendingPathComponent("\(entry.id.uuidString).json"))
            if URL(fileURLWithPath: entry.logPath).deletingLastPathComponent().standardizedFileURL == logs.standardizedFileURL {
                try? FileManager.default.removeItem(atPath: entry.logPath)
            }
        }
    }
    public func history() -> [ScanRecord] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: records, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.compactMap {
            guard let data = try? Data(contentsOf: $0) else { return nil }
            return try? JSONDecoder().decode(ScanRecord.self, from: data)
        }.sorted { $0.started > $1.started }
    }
    public var definitionsDate: Date? {
        let urls = (try? FileManager.default.contentsOfDirectory(at: database, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        // daily is a better freshness signal than the rarely updated main database.
        return urls.filter { ["daily.cvd", "daily.cld"].contains($0.lastPathComponent) }
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max()
    }
    public var hasDefinitions: Bool {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: database.path)) ?? []
        return files.contains { $0.hasSuffix(".cvd") || $0.hasSuffix(".cld") }
    }
    public func writeFreshclamConfig() throws {
        try prepare()
        // No system config changes; no daemon; database is owned by the logged-in user.
        let text = """
        DatabaseDirectory "\(database.path)"
        DatabaseMirror database.clamav.net
        DNSDatabaseInfo current.cvd.clamav.net
        ScriptedUpdates yes
        CompressLocalDatabase yes
        TestDatabases yes
        ConnectTimeout 30
        ReceiveTimeout 300
        """
        try Data(text.utf8).write(to: config, options: .atomic)
    }
}

/// One engine operation across GUI and LaunchAgent, released by the kernel after a crash.
public final class OperationLock {
    private var descriptor: Int32 = -1
    public init(storage: Storage) throws {
        try storage.prepare()
        descriptor = open(storage.root.appendingPathComponent("operation.lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw MarsError.message("Cannot open the engine lock.") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor); descriptor = -1
            throw MarsError.message("Another mars scan or definition update is already running. Try again when it finishes.")
        }
    }
    deinit { if descriptor >= 0 { flock(descriptor, LOCK_UN); close(descriptor) } }
}
