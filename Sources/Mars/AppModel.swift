import AppKit
import SwiftUI
import UniformTypeIdentifiers
import MarsCore

@MainActor
final class AppModel: ObservableObject {
    @Published var page: Page = .overview
    @Published var preferences = Preferences()
    @Published var history: [ScanRecord] = []
    @Published var installed = Engine.installed
    @Published var definitionsDate: Date?
    @Published var hasDefinitions = false
    @Published var busy = false
    @Published var operation = ""
    @Published var activity: [String] = []
    @Published var error: String?
    @Published var selectedRecord: ScanRecord?
    @Published var showInstallConfirmation = false
    @Published var showHomebrewConfirmation = false
    let storage = Storage()
    let demo = ProcessInfo.processInfo.arguments.contains("--demo")
    private var cancellation = Cancellation()
    private var refreshTimer: Timer?

    enum Page: String, CaseIterable, Identifiable {
        case overview = "Overview", scan = "Scan", schedule = "Schedule", history = "History", settings = "Settings"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .overview: return "square.grid.2x2"
            case .scan: return "viewfinder"
            case .schedule: return "calendar"
            case .history: return "clock.arrow.circlepath"
            case .settings: return "slider.horizontal.3"
            }
        }
    }

    init() {
        preferences = storage.preferences()
        refresh()
        if demo {
            installed = true; hasDefinitions = true; definitionsDate = Date()
            var record = ScanRecord(scope: .home, targets: ["/Users/demo"])
            record.started = Date().addingTimeInterval(-7200)
            record.finished = record.started.addingTimeInterval(183)
            record.scannedFiles = 24861; record.outcome = .completed
            record.note = "Synthetic preview data. No real scan has run."
            history = [record]
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "--page"), arguments.indices.contains(index + 1),
               let requested = Page.allCases.first(where: { $0.rawValue.lowercased() == arguments[index + 1] }) { page = requested }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.busy && !self.demo else { return }
                self.refresh()
            }
        }
    }
    func refresh() {
        guard !demo else { return }
        installed = Engine.installed
        hasDefinitions = storage.hasDefinitions
        definitionsDate = storage.definitionsDate
        history = storage.history()
    }
    var ready: Bool { installed && hasDefinitions }
    var latest: ScanRecord? { history.first }
    var definitionsStale: Bool { definitionsDate.map { Date().timeIntervalSince($0) > 172800 } ?? true }
    var freshness: String {
        guard let definitionsDate else { return "Not downloaded" }
        return definitionsDate.formatted(.relative(presentation: .named))
    }
    var scheduleSummary: String {
        guard preferences.scheduleEnabled else { return "Not scheduled" }
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let day = preferences.weekly ? days[min(6, max(0, preferences.weekday))] : "Every day"
        return "\(day) at \(String(format: "%02d:%02d", preferences.hour, preferences.minute))"
    }
    func run(_ title: String, work: @escaping (Cancellation, @escaping (String) -> Void) throws -> ScanRecord?) {
        guard !busy else { return }
        guard !demo else { error = "This is a visual preview. Open Mars normally to use the engine."; return }
        busy = true; operation = title; activity = []; cancellation = Cancellation()
        let token = cancellation
        DispatchQueue.global(qos: .utility).async {
            let emit: (String) -> Void = { text in
                DispatchQueue.main.async {
                    self.activity.append(text)
                    if self.activity.count > 400 { self.activity.removeFirst(self.activity.count - 400) }
                }
            }
            do {
                let record = try work(token, emit)
                DispatchQueue.main.async {
                    self.busy = false; self.operation = ""
                    self.refresh()
                    if let record { self.selectedRecord = record }
                }
            } catch {
                DispatchQueue.main.async {
                    self.busy = false; self.operation = ""; self.refresh()
                    self.error = token.isCancelled ? "Operation cancelled. No files were changed." : error.localizedDescription
                }
            }
        }
    }
    func install() {
        if Engine.brew == nil { showHomebrewConfirmation = true; return }
        showInstallConfirmation = true
    }
    func installConfirmed() {
        let engine = Engine(storage: storage)
        run("Installing ClamAV") { token, emit in
            try engine.install(cancellation: token, line: emit)
            emit("ClamAV installed. Downloading definitions…")
            try engine.update(cancellation: token, line: emit)
            return nil
        }
    }
    func updateDefinitions() {
        let engine = Engine(storage: storage)
        run("Updating definitions") { token, emit in
            try engine.update(cancellation: token, line: emit); return nil
        }
    }
    func startScan() {
        do { _ = try Engine.targets(for: preferences) } catch { self.error = error.localizedDescription; return }
        let engine = Engine(storage: storage)
        let snapshot = preferences
        run("Scanning your Mac") { token, emit in
            try engine.scan(preferences: snapshot, cancellation: token, line: emit)
        }
    }
    func cancel() { operation = "Stopping safely…"; cancellation.cancel() }
    func chooseFolders() {
        let panel = NSOpenPanel()
        panel.title = "Choose folders for Mars to scan"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            preferences.folders = panel.urls.map(\.path)
            preferences.scope = .folders
        }
    }
    func saveSchedule() {
        guard !demo else { return }
        let old = storage.preferences()
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/mars-scan").path
        do {
            if preferences.scheduleEnabled { _ = try Engine.targets(for: preferences) }
            try storage.save(preferences)
            try Scheduler.apply(preferences: preferences, helper: helper, storage: storage)
            activity = [preferences.scheduleEnabled ? "Schedule saved. \(scheduleSummary)." : "Scheduled scans disabled."]
        } catch {
            try? storage.save(old)
            try? Scheduler.apply(preferences: old, helper: helper, storage: storage)
            preferences = old
            self.error = error.localizedDescription
        }
    }
    func saveScanPreferences() {
        guard !demo else { return }
        var saved = storage.preferences()
        saved.scope = preferences.scope
        saved.folders = preferences.folders
        saved.updateBeforeScan = preferences.updateBeforeScan
        do { try storage.save(saved) } catch { self.error = error.localizedDescription }
    }
    func export(_ record: ScanRecord) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Mars-scan-\(record.id.uuidString.prefix(8)).json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(record).write(to: url, options: .atomic)
            } catch { self.error = error.localizedDescription }
        }
    }
    func open(_ address: String) {
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }
    func installHomebrew() {
        // Static command, explicit confirmation, visible Terminal. Mars never receives the password.
        let command = #"/bin/bash -c "$(/usr/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var details: NSDictionary?
        NSAppleScript(source: "tell application \"Terminal\"\nactivate\ndo script \"\(escaped)\"\nend tell")?
            .executeAndReturnError(&details)
        if let details { error = "Could not open the Homebrew installer in Terminal: \(details). You can install it from brew.sh instead." }
    }
}
