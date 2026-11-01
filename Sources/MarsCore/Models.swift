import Foundation

public enum ScanScope: String, Codable, CaseIterable {
    case mac, home, folders
    public var title: String {
        switch self {
        case .mac: return "Entire Mac"
        case .home: return "Home folder"
        case .folders: return "Selected folders"
        }
    }
}

public enum ScanOutcome: String, Codable {
    case completed, threatsFound, incomplete, failed, cancelled
    public var title: String {
        switch self {
        case .completed: return "No threats detected"
        case .threatsFound: return "Items need your review"
        case .incomplete: return "Scan incomplete"
        case .failed: return "Scan failed"
        case .cancelled: return "Scan cancelled"
        }
    }
}

public struct Finding: Codable, Identifiable, Equatable {
    public var id: UUID = UUID()
    public var path: String
    public var signature: String
    public var engine: String?
    public var source: String?
    public var assessment: String?
    public init(path: String, signature: String) { self.path = path; self.signature = signature }
    public var explanation: String {
        if signature.contains("Heuristics.Limits.Exceeded") {
            return "ClamAV reached an inspection limit. This label describes incomplete coverage, not identification of malware."
        }
        if signature.lowercased().contains("eicar") {
            return "This label refers to an antivirus test pattern. Confirm you intentionally obtained a test file; the label alone does not establish that the entire file is safe."
        }
        if engine == "YARA-X" {
            return "A rule matched byte patterns or conditions in the file. This is useful evidence to review, not a confirmed infection or an automatic assessment of intent."
        }
        if signature.hasPrefix("Heuristics.") {
            return "A heuristic identified a suspicious characteristic rather than necessarily matching a known malicious sample. Legitimate files can sometimes trigger these checks."
        }
        return "The engine reported this detection label. Review its source and the file's origin before deciding what to do; a false positive remains possible."
    }
}

public struct ScanRecord: Codable, Identifiable {
    public var id = UUID()
    public var started = Date()
    public var finished: Date?
    public var scope: ScanScope
    public var targets: [String]
    public var outcome: ScanOutcome = .failed
    public var findings: [Finding] = []
    public var scannedFiles = 0
    public var warnings = 0
    public var exitCode: Int32 = -1
    public var scheduled = false
    public var logPath = ""
    public var note = ""
    public var passes: [ScanPass]?
    public var coverageNotes: [String]?
    public var baselineFinished: Bool {
        passes?.contains { $0.engine == "ClamAV" && $0.source == "Official ClamAV" && ["completed", "threatsFound"].contains($0.status) } == true
    }
    public var displayTitle: String {
        if outcome == .incomplete && baselineFinished && passes?.contains(where: { $0.status == "notRun" }) == true {
            return "Baseline finished; optional checks skipped"
        }
        return outcome.title
    }
    public init(scope: ScanScope, targets: [String]) { self.scope = scope; self.targets = targets }
}

public struct Preferences: Codable, Equatable {
    public var scope: ScanScope = .home
    public var folders: [String] = []
    public var scheduleEnabled = false
    public var weekly = false
    public var weekday = 1 // launchd: Sunday = 0
    public var hour = 12
    public var minute = 0
    public var updateBeforeScan = true
    public var yaraXEnabled: Bool?
    public init() {}
}

public struct ScanPass: Codable, Identifiable {
    public var id = UUID()
    public var engine: String
    public var source: String
    public var status: String
    public var files: Int
    public var findings: Int
    public var warnings: Int
    public var logPath: String
    public var countMeaning: String
    public var statusTitle: String {
        switch status {
        case "completed": return "Finished"
        case "threatsFound": return "Matches to review"
        case "incomplete": return "Coverage limited"
        case "failed": return "Could not finish"
        case "cancelled": return "Stopped by you"
        case "notRun": return "Did not run"
        default: return status
        }
    }
    public init(engine: String, source: String, status: String, files: Int = 0, findings: Int = 0,
                warnings: Int = 0, logPath: String = "", countMeaning: String = "engine-reported files") {
        self.engine = engine; self.source = source; self.status = status; self.files = files
        self.findings = findings; self.warnings = warnings; self.logPath = logPath; self.countMeaning = countMeaning
    }
}

public struct ScanUpdate {
    public var stage: String
    public var explanation: String
    public var source: String
    public var completedPasses: Int
    public var totalPasses: Int
    public var observedFiles: Int
    public var findings: Int
    public var currentPath: String
    public init(stage: String, explanation: String, source: String = "", completedPasses: Int = 0,
                totalPasses: Int = 0, observedFiles: Int = 0, findings: Int = 0, currentPath: String = "") {
        self.stage = stage; self.explanation = explanation; self.source = source
        self.completedPasses = completedPasses; self.totalPasses = totalPasses
        self.observedFiles = observedFiles; self.findings = findings; self.currentPath = currentPath
    }
}

public enum Interpretation {
    public static func summary(_ record: ScanRecord) -> String {
        switch record.outcome {
        case .completed: return "The selected checks finished without reporting a match. This is reassuring, but it does not prove every file is safe."
        case .threatsFound: return "One or more signatures or rules matched. A match can indicate malware, a suspicious pattern, or a false positive. Do not open a flagged file while you investigate."
        case .incomplete:
            if record.baselineFinished {
                return "ClamAV finished its baseline check, but not all requested optional checks completed. Review the skipped sources and coverage notes below. This is not a failure to start, and it is not a guarantee that all files are safe."
            }
            return "Mars could not finish checking everything requested. Missing permissions, unreadable files, or engine limits can leave gaps; an empty finding list is not a clean bill of health."
        case .failed: return "The scan could not complete. Read the explanation and engine console, fix the setup or update problem, then try a small folder again."
        case .cancelled: return "You stopped this scan. Any findings already recorded are still worth reviewing, but the remaining files were not checked."
        }
    }
    public static func nextSteps(_ record: ScanRecord) -> [String] {
        var steps: [String] = []
        if !record.findings.isEmpty { steps += ["Do not open or run flagged files.", "Check the rule name, source, and file location. A rule match is not confirmation of infection.", "If this looks like a real compromise, disconnect from networks and seek trusted help before changing evidence."] }
        if record.warnings > 0 || [.incomplete, .failed].contains(record.outcome) {
            if record.baselineFinished && record.passes?.contains(where: { $0.status == "notRun" }) == true {
                steps += ["Open Engines & sources to configure or turn off skipped optional sources. No subscription is required for the ClamAV baseline.",
                    "Review coverage notes and logs, then retry a smaller known folder if needed."]
            } else {
                steps += ["Review coverage notes and logs; grant only the access you intend to allow.", "Update the enabled sources, then retry a smaller known folder."]
            }
        }
        if record.outcome == .completed { steps += ["Keep macOS, the scanning engines, and definitions updated.", "Save a scan routine if useful. Mars does not provide real-time protection."] }
        if record.outcome == .cancelled { steps.append("Run another scan when convenient; cancelled work is not automatically resumed.") }
        steps.append("Mars has not deleted, moved, or quarantined anything.")
        return steps
    }
}

public enum MarsError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

public struct ScanParser {
    public private(set) var findings: [Finding] = []
    public private(set) var scannedFiles = 0
    public private(set) var warnings = 0
    public init() {}

    public mutating func consume(_ line: String) {
        if line.hasSuffix(" FOUND"), let separator = line.range(of: ": ", options: .backwards) {
            let path = String(line[..<separator.lowerBound])
            let signature = String(line[separator.upperBound...].dropLast(6))
            var finding = Finding(path: path, signature: signature)
            finding.assessment = signature.contains("Heuristics.Limits.Exceeded") ? "Coverage limit, not a malware verdict" : "Signature match; verify before acting"
            findings.append(finding)
            if signature.contains("Heuristics.Limits.Exceeded") { warnings += 1 }
        }
        if line.hasPrefix("Scanned files:"),
           let value = Int(line.dropFirst("Scanned files:".count).trimmingCharacters(in: .whitespaces)) {
            scannedFiles = value
        }
        if line.contains("ERROR") || line.contains("WARNING") { warnings += 1 }
    }

    public func outcome(exitCode: Int32, cancelled: Bool) -> ScanOutcome {
        if cancelled { return .cancelled }
        if !findings.isEmpty { return .threatsFound }
        if exitCode == 2 || (exitCode == 0 && (warnings > 0 || scannedFiles == 0)) { return .incomplete }
        if exitCode != 0 { return .failed }
        return .completed
    }
}
