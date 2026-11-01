import SwiftUI
import AppKit
import MarsCore

struct ScanJourneyView: View {
    @EnvironmentObject var model: AppModel
    @State private var consoleExpanded = true
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 14) {
                        if model.busy { ProgressView().controlSize(.regular).padding(.top, 5) }
                        else { Image(systemName: "checkmark.circle").font(.system(size: 25)).foregroundStyle(Palette.green) }
                        VStack(alignment: .leading, spacing: 7) {
                            Text(model.busy ? (model.scanUpdate?.stage ?? model.operation) : "Engine activity finished")
                                .font(.system(size: 18, weight: .medium, design: .serif))
                            Text(model.busy ? (model.scanUpdate?.explanation ?? "The engine is working locally. Initial setup and database loading can take a little while.") : "Open a report in History to understand the result. Activity completion alone is not a clean scan verdict.")
                                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                        }
                        Spacer()
                        if model.busy { Button("Stop safely") { model.cancel() } }
                    }
                    if let update = model.scanUpdate {
                        HStack(spacing: 24) {
                            Label("\(update.completedPasses) / \(update.totalPasses) checks finished", systemImage: "square.stack")
                            if update.observedFiles > 0 { Label("\(update.observedFiles.formatted()) file results observed", systemImage: "doc") }
                            Label("\(update.findings) matches so far", systemImage: "shield")
                        }.font(.system(size: 10)).foregroundStyle(.secondary)
                        if !update.currentPath.isEmpty {
                            Text(update.currentPath).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle).help(update.currentPath)
                        }
                    }
                    HStack {
                        Label("No files changed · no uploads", systemImage: "lock")
                        Spacer()
                        if let start = model.operationStarted {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text("Elapsed \(Int((model.busy ? context.date : (model.operationFinished ?? context.date)).timeIntervalSince(start)))s")
                            }
                        }
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                    Text("Why no percentage? Engines may discover archive members or take longer on certain files. Mars shows real stages and observed counts instead of guessing how much is left.")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
                }
            }
            DisclosureGroup(isExpanded: $consoleExpanded) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        HStack(spacing: 5) { ForEach(0..<3) { _ in Circle().fill(Color.white.opacity(0.18)).frame(width: 6, height: 6) } }
                        Text("ENGINE CONSOLE · READ-ONLY").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1)
                        Spacer()
                        Button("Copy visible log") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.activity.joined(separator: "\n"), forType: .string) }
                            .buttonStyle(.plain).font(.system(size: 10))
                    }.padding(13).foregroundStyle(.white.opacity(0.55))
                    Divider().overlay(.white.opacity(0.1))
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(model.activity.suffix(120).joined(separator: "\n"))
                                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Color(red: 0.69, green: 0.84, blue: 0.75))
                                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                Color.clear.frame(height: 1).id("tail")
                            }.padding(14)
                        }.frame(height: 190)
                            .onChange(of: model.consoleGeneration) { _ in proxy.scrollTo("tail", anchor: .bottom) }
                    }
                }.background(Palette.ink, in: RoundedRectangle(cornerRadius: 12)).padding(.top, 10)
            } label: {
                HStack {
                    Image(systemName: "terminal")
                    Text("See exactly what the engines are saying").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("Optional technical detail").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ScanResultsView: View {
    let record: ScanRecord
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var showTechnical = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: record.outcome == .completed ? "checkmark.shield" : "exclamationmark.shield")
                    .font(.system(size: 32)).foregroundStyle(record.outcome == .completed ? Palette.green : Palette.red)
                VStack(alignment: .leading, spacing: 5) {
                    Text(record.displayTitle).font(.system(size: 25, weight: .medium, design: .serif))
                    Text("\(record.scope.title) · \(record.started.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(26)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Card {
                        VStack(alignment: .leading, spacing: 13) {
                            Text("What this means").font(.system(size: 18, weight: .medium, design: .serif))
                            Text(Interpretation.summary(record)).font(.system(size: 13)).lineSpacing(5)
                            HStack(spacing: 22) {
                                Label("Baseline files: \(record.scannedFiles.formatted())", systemImage: "doc")
                                Label("Matches: \(record.findings.count)", systemImage: "shield")
                                Label("Coverage warnings: \(record.warnings)", systemImage: "exclamationmark.triangle")
                            }.font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    if record.outcome == .failed && !record.note.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 9) {
                                Text("Why this stopped").font(.system(size: 15, weight: .semibold))
                                Text(record.note).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                                Text("No scan result should be inferred from a failure to start. Check the indicated setup step, then prepare another scan.")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if record.warnings > 0 || record.exitCode == 2 || record.outcome == .incomplete {
                        Label("Coverage was limited. Review the notes below even if no matches were found.", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.red)
                    }
                    if !record.findings.isEmpty {
                        Text("Items to investigate").font(.system(size: 20, weight: .medium, design: .serif))
                        ForEach(record.findings) { finding in
                            Card {
                                VStack(alignment: .leading, spacing: 11) {
                                    Text(finding.assessment ?? "Signature match; verify before acting").font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.red)
                                    Text(finding.signature).font(.system(size: 13, weight: .semibold)).textSelection(.enabled)
                                    Text(finding.explanation).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                                    Text("\(finding.engine ?? "ClamAV") · \(finding.source ?? "Source not recorded by this older app version")")
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                    Text(finding.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                    HStack {
                                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: finding.path)]) }
                                        Button("Copy path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(finding.path, forType: .string) }
                                        Spacer()
                                        Text("No automatic removal").font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    Text("Recommended next steps").font(.system(size: 20, weight: .medium, design: .serif))
                    Card {
                        VStack(alignment: .leading, spacing: 13) {
                            ForEach(Array(Interpretation.nextSteps(record).enumerated()), id: \.offset) { index, text in
                                HStack(alignment: .top, spacing: 11) {
                                    Text("\(index + 1)").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.red).frame(width: 18)
                                    Text(text).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                                }
                            }
                        }
                    }
                    if let passes = record.passes, !passes.isEmpty {
                        Text("Which checks ran?").font(.system(size: 20, weight: .medium, design: .serif))
                        ForEach(passes) { pass in
                            HStack(alignment: .top) {
                                Image(systemName: pass.status == "completed" ? "checkmark.circle" : "info.circle").foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("\(pass.engine) · \(pass.source)").font(.system(size: 12, weight: .semibold))
                                    Text("\(pass.statusTitle) · \(pass.files.formatted()) \(pass.countMeaning) · \(pass.findings) matches")
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !pass.logPath.isEmpty { Button("Console log") { openLog(pass.logPath) }.font(.system(size: 10)) }
                            }
                        }
                    }
                    DisclosureGroup(isExpanded: $showTechnical) {
                        VStack(alignment: .leading, spacing: 13) {
                            Text(record.note).font(.system(size: 11)).textSelection(.enabled)
                            ForEach(record.coverageNotes ?? [], id: \.self) { note in Text("• \(note)").font(.system(size: 11)).foregroundStyle(.secondary) }
                            Text(record.targets.joined(separator: "\n")).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                            Text("ClamAV baseline exit code: \(record.exitCode). Counts from repeated passes are not added together as unique files.")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }.padding(.top, 10)
                    } label: { Text("Coverage, scope & technical details").font(.system(size: 12, weight: .medium)) }
                }.padding(26)
            }
            Divider()
            HStack {
                Button("Export report…") { model.export(record) }
                Button("Review scan console") { openLog(record.logPath) }.disabled(!FileManager.default.fileExists(atPath: record.logPath))
                Button("Privacy settings") { model.open("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") }
                Button("Engines & sources") { dismiss(); model.page = .sources }
                Spacer()
                PrimaryButton(title: "Prepare another scan", icon: "arrow.clockwise") { dismiss(); model.rescan(record) }
            }.padding(20)
        }.frame(width: 850, height: 720).background(Palette.background)
            .onAppear { showTechnical = record.warnings > 0 || record.outcome == .incomplete }
    }
    private func openLog(_ path: String) {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            model.error = "No scan console log exists. The operation may have stopped before an engine started. Check Logs/definitions.log for update failures."; return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
