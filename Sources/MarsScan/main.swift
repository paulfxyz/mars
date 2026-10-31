import Foundation
import MarsCore

let storage = Storage()
let preferences = storage.preferences()
guard preferences.scheduleEnabled else { exit(0) }
do {
    let result = try Engine(storage: storage).scan(preferences: preferences, scheduled: true, cancellation: Cancellation()) { print($0) }
    print("\(result.outcome.title): \(result.scannedFiles) files; \(result.findings.count) detections; \(result.warnings) warnings.")
    exit(result.outcome == .completed ? 0 : (result.outcome == .threatsFound ? 1 : 2))
} catch {
    fputs("mars: \(error.localizedDescription)\n", stderr)
    exit(2)
}
