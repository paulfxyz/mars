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
        case .threatsFound: return "Threats detected"
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
    public init(path: String, signature: String) { self.path = path; self.signature = signature }
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
    public init() {}
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
            findings.append(Finding(path: path, signature: signature))
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
        if exitCode == 2 || (exitCode == 0 && warnings > 0) { return .incomplete }
        if exitCode != 0 { return .failed }
        return .completed
    }
}
