import Foundation

public struct Scheduler {
    public static let label = "com.paulfleury.mars.scan"
    public static var plist: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    public static func propertyList(preferences: Preferences, helper: String, logs: URL) -> [String: Any] {
        var calendar = ["Hour": preferences.hour, "Minute": preferences.minute]
        if preferences.weekly { calendar["Weekday"] = preferences.weekday }
        return [
            "Label": label,
            "ProgramArguments": [helper],
            "StartCalendarInterval": calendar,
            "ProcessType": "Background",
            "LowPriorityIO": true,
            "Nice": 10,
            "StandardOutPath": logs.appendingPathComponent("schedule.log").path,
            "StandardErrorPath": logs.appendingPathComponent("schedule-error.log").path
        ]
    }
    public static func apply(preferences: Preferences, helper: String, storage: Storage) throws {
        guard (0...23).contains(preferences.hour), (0...59).contains(preferences.minute),
              (0...6).contains(preferences.weekday) else { throw MarsError.message("Invalid schedule time.") }
        try storage.prepare()
        let domain = "gui/\(getuid())"
        // Unload only our own job. Not-loaded is expected on first use.
        _ = try ProcessRunner.run("/bin/launchctl", ["bootout", "\(domain)/\(label)"])
        if !preferences.scheduleEnabled {
            if FileManager.default.fileExists(atPath: plist.path) { try FileManager.default.removeItem(at: plist) }
            return
        }
        guard FileManager.default.isExecutableFile(atPath: helper) else {
            throw MarsError.message("The scheduled-scan helper is missing. Install the complete mars.app in Applications.")
        }
        try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: propertyList(preferences: preferences, helper: helper, logs: storage.logs), format: .xml, options: 0)
        try data.write(to: plist, options: .atomic)
        var details: [String] = []
        let code = try ProcessRunner.run("/bin/launchctl", ["bootstrap", domain, plist.path]) { details.append($0) }
        guard code == 0 else { throw MarsError.message("macOS could not load the schedule: \(details.joined(separator: "\n"))") }
    }
}
