import AppKit
import SwiftUI
import UniformTypeIdentifiers
import MarsCore

@MainActor
final class AppModel: ObservableObject {
    @Published var page: Page = .overview
    @Published var preferences = Preferences()
    @Published var savedPreferences = Preferences()
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
    @Published var sources: [DetectionSource] = []
    @Published var yaraXInstalled = Engine.yaraXInstalled
    @Published var sourceConsent: DetectionSource?
    @Published var optionalPackage: String?
    @Published var showPrivateFeedSetup = false
    @Published var scanUpdate: ScanUpdate?
    @Published var operationStarted: Date?
    @Published var operationFinished: Date?
    @Published var consoleGeneration = 0
    let storage = Storage()
    let demo = ProcessInfo.processInfo.arguments.contains("--demo")
    private var cancellation = Cancellation()
    private var refreshTimer: Timer?

    enum Page: String, CaseIterable, Identifiable {
        case overview = "Overview", scan = "Scan", sources = "Detection Sources", schedule = "Schedule", history = "History", settings = "Settings"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .overview: return "square.grid.2x2"
            case .scan: return "viewfinder"
            case .sources: return "square.stack.3d.up"
            case .schedule: return "calendar"
            case .history: return "clock.arrow.circlepath"
            case .settings: return "slider.horizontal.3"
            }
        }
    }

    init() {
        preferences = storage.preferences()
        savedPreferences = preferences
        refresh()
        if demo {
            preferences = Preferences(); savedPreferences = preferences
            installed = true; hasDefinitions = true; definitionsDate = Date()
            sources = Catalog.defaults; yaraXInstalled = true
            var record = ScanRecord(scope: .home, targets: ["/Users/demo"])
            record.started = Date().addingTimeInterval(-7200)
            record.finished = record.started.addingTimeInterval(183)
            record.scannedFiles = 24861; record.outcome = .completed
            record.note = "Synthetic preview data. No real scan has run."
            history = [record]
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "--page"), arguments.indices.contains(index + 1),
               let requested = Page.allCases.first(where: { $0.rawValue.lowercased() == arguments[index + 1] }) { page = requested }
            if arguments.contains("--sources") { page = .sources }
            if arguments.contains("--scanning") {
                page = .scan; busy = true; operation = "Scanning your selected folders"
                operationStarted = Date().addingTimeInterval(-82)
                scanUpdate = ScanUpdate(stage: "YARA-X · Mac starter rules", explanation: "Checking suspicious patterns locally. A rule match is a reason to investigate, not proof of infection.",
                    source: "Elastic Mac starter rules", completedPasses: 1, totalPasses: 2, observedFiles: 24861, findings: 0)
                activity = ["[ClamAV / Official] Scanned files: 24861", "[ClamAV / Official] Infected files: 0", "[YARA-X] Starting local pattern analysis…", "Synthetic console output; no real files were scanned."]
            }
            if arguments.contains("--results") {
                var finding = Finding(path: "/Users/demo/Downloads/example-app", signature: "Illustrative_Mac_Pattern")
                finding.engine = "YARA-X"; finding.source = "Illustrative demo source"; finding.assessment = "Synthetic rule match; not real malware"
                record.findings = [finding]; record.outcome = .threatsFound; record.warnings = 1
                record.coverageNotes = ["Illustrative permission warning: one folder could not be checked."]
                record.passes = [ScanPass(engine: "ClamAV", source: "Official ClamAV", status: "completed", files: 24861),
                    ScanPass(engine: "YARA-X", source: "Illustrative demo source", status: "completed", files: 100, findings: 1, countMeaning: "candidate files submitted")]
                let previewRecord = record
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.selectedRecord = previewRecord }
            }
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
        savedPreferences = storage.preferences()
        sources = storage.sources()
        yaraXInstalled = Engine.yaraXInstalled
    }
    var ready: Bool { installed && hasDefinitions }
    var latest: ScanRecord? { history.first }
    var definitionsStale: Bool { definitionsDate.map { Date().timeIntervalSince($0) > 172800 } ?? true }
    var freshness: String {
        guard let definitionsDate else { return "Not downloaded" }
        return definitionsDate.formatted(.relative(presentation: .named))
    }
    var scheduleSummary: String {
        guard savedPreferences.scheduleEnabled else { return "Not scheduled" }
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let day = savedPreferences.weekly ? days[min(6, max(0, savedPreferences.weekday))] : "Every day"
        return "\(day) at \(String(format: "%02d:%02d", savedPreferences.hour, savedPreferences.minute))"
    }
    func run(_ title: String, work: @escaping (Cancellation, @escaping (String) -> Void) throws -> ScanRecord?) {
        guard !busy else { return }
        guard !demo else { error = "This is a visual preview. Open Mars normally to use the engine."; return }
        busy = true; operation = title; activity = []; cancellation = Cancellation()
        scanUpdate = nil; operationStarted = Date(); operationFinished = nil
        let token = cancellation
        DispatchQueue.global(qos: .utility).async {
            let relay = ConsoleRelay { lines in
                self.activity.append(contentsOf: lines)
                if self.activity.count > 400 { self.activity.removeFirst(self.activity.count - 400) }
                self.consoleGeneration += 1
            }
            let emit: (String) -> Void = { relay.append($0) }
            do {
                let record = try work(token, emit)
                relay.flush()
                DispatchQueue.main.async {
                    self.busy = false; self.operation = ""
                    self.operationFinished = Date()
                    self.refresh()
                    if let record { self.selectedRecord = record }
                }
            } catch {
                relay.flush()
                DispatchQueue.main.async {
                    self.busy = false; self.operation = ""; self.refresh()
                    self.operationFinished = Date()
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
        page = .scan
        run("Scanning your Mac") { token, emit in
            try engine.scan(preferences: snapshot, cancellation: token, progress: { update in
                DispatchQueue.main.async { self.scanUpdate = update }
            }, line: emit)
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
            savedPreferences = preferences
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
        saved.yaraXEnabled = preferences.yaraXEnabled
        do { try storage.save(saved); savedPreferences = saved } catch { self.error = error.localizedDescription }
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
    func enableSource(_ source: DetectionSource) {
        guard !demo else { return }
        if !source.enabled && !source.acceptedTerms { sourceConsent = source; return }
        changeSource(source.id) { $0.enabled.toggle() }
    }
    func acceptSource(_ source: DetectionSource) {
        changeSource(source.id) { $0.acceptedTerms = true; $0.enabled = true }
        sourceConsent = nil
    }
    private func changeSource(_ id: String, edit: (inout DetectionSource) -> Void) {
        guard !busy, !demo else { return }
        do {
            let operationLock = try OperationLock(storage: storage)
            defer { withExtendedLifetime(operationLock) {} }
            var values = storage.sources()
            guard let index = values.firstIndex(where: { $0.id == id }) else { return }
            edit(&values[index]); try storage.saveSources(values); refresh()
        } catch { self.error = error.localizedDescription }
    }
    func updateSource(_ source: DetectionSource) {
        let manager = SourceManager(storage: storage)
        run("Updating \(source.name)") { token, emit in try manager.update(id: source.id, cancellation: token, line: emit); return nil }
    }
    func rollbackSource(_ source: DetectionSource) {
        guard !demo, !busy else { return }
        do { try SourceManager(storage: storage).rollback(id: source.id); refresh() } catch { self.error = error.localizedDescription }
    }
    func installOptionalConfirmed(_ package: String) {
        optionalPackage = nil
        let engine = Engine(storage: storage)
        run("Installing \(package)") { token, emit in try engine.installOptional(package: package, cancellation: token, line: emit); return nil }
    }
    func importSource(engine: DetectionEngine) {
        guard !busy, !demo else { return }
        let alert = NSAlert()
        alert.messageText = "Import trusted \(engine.rawValue) definitions?"
        alert.informativeText = "Rules are not guaranteed safe or accurate. Confirm you trust the source and have rights to use these files. Standalone rules only; includes and compiled YARA are rejected. Imported packs do not update automatically."
        alert.addButton(withTitle: "Choose files"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        let files = panel.urls, manager = SourceManager(storage: storage)
        run("Validating imported definitions") { token, emit in
            try manager.importFiles(files, name: "Imported \(engine.rawValue) · \(Date().formatted(date: .abbreviated, time: .shortened))",
                engine: engine, cancellation: token, line: emit); return nil
        }
    }
    func savePrivateFeeds(_ text: String) {
        guard !demo, !busy else { return }
        do {
            let operationLock = try OperationLock(storage: storage)
            defer { withExtendedLifetime(operationLock) {} }
            try storage.setPrivateFeeds(text); showPrivateFeedSetup = false
        } catch { self.error = error.localizedDescription }
    }
    func rescan(_ record: ScanRecord) {
        selectedRecord = nil; page = .scan
        preferences.scope = record.scope
        if record.scope == .folders { preferences.folders = record.targets }
        // A fresh scan is explicit; this action only restores scope, never starts work secretly.
    }
}

/// A bounded relay keeps verbose per-file terminal output from flooding the main queue.
final class ConsoleRelay {
    private var buffer: [String] = []
    private var last = Date.distantPast
    private let deliver: @MainActor ([String]) -> Void
    init(deliver: @escaping @MainActor ([String]) -> Void) { self.deliver = deliver }
    func append(_ line: String) {
        buffer.append(line)
        if buffer.count > 400 { buffer.removeFirst(buffer.count - 400) }
        if Date().timeIntervalSince(last) > 0.15 { flush() }
    }
    func flush() {
        guard !buffer.isEmpty else { return }
        let lines = buffer; buffer = []; last = Date()
        DispatchQueue.main.async { self.deliver(lines) }
    }
}
