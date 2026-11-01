import SwiftUI
import AppKit
import MarsCore

enum Palette {
    static let red = Color(red: 0.76, green: 0.22, blue: 0.16)
    static let green = Color(red: 0.15, green: 0.45, blue: 0.36)
    static let ink = Color(red: 0.12, green: 0.14, blue: 0.14)
    static let background = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.105, alpha: 1)
            : NSColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1)
    })
    static let card = Color(nsColor: .controlBackgroundColor)
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                HStack {
                    Text(model.page.rawValue).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    if model.demo { Label("ILLUSTRATIVE PREVIEW", systemImage: "sparkles").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary) }
                    Circle().fill(model.busy ? Color.orange : Palette.green).frame(width: 6, height: 6)
                    Text(model.busy ? model.operation : "Local scans. No uploads.").font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(.horizontal, 32).frame(height: 54)
                Divider().opacity(0.5)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch model.page {
                        case .overview: OverviewView()
                        case .scan: ScanView()
                        case .sources: DetectionSourcesView()
                        case .schedule: ScheduleView()
                        case .history: HistoryView()
                        case .settings: SettingsView()
                        }
                        if (model.busy || !model.activity.isEmpty) && !(model.page == .scan && model.busy) { ActivityView() }
                        HStack(spacing: 5) {
                            Image(systemName: "lock")
                            Text("Your files stay on your Mac. Mars never removes them.")
                        }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 3)
                    }.padding(32).frame(maxWidth: 1080, alignment: .leading).frame(maxWidth: .infinity)
                }
            }.background(Palette.background)
        }
        .tint(Palette.red)
        .sheet(item: $model.selectedRecord) { record in RecordView(record: record).environmentObject(model) }
        .sheet(item: $model.sourceConsent) { source in SourceConsentView(source: source).environmentObject(model) }
        .sheet(isPresented: $model.showPrivateFeedSetup) { PrivateFeedsView().environmentObject(model) }
        .alert("Install optional component?", isPresented: Binding(get: { model.optionalPackage != nil }, set: { if !$0 { model.optionalPackage = nil } })) {
            Button("Install with Homebrew") { if let package = model.optionalPackage { model.installOptionalConfirmed(package) } }
            Button("Cancel", role: .cancel) { model.optionalPackage = nil }
        } message: { Text("Mars will install \(model.optionalPackage == "gnupg" ? "GnuPG and a current rsync for signed-feed verification" : "YARA-X") with Homebrew. Older or Intel Macs may require source builds. You can still use ClamAV if an optional component is unavailable.") }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13).fill(Palette.red.gradient).frame(width: 40, height: 40)
                    Image(systemName: "shield.lefthalf.filled").font(.system(size: 22, weight: .medium)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Mars").font(.system(size: 26, weight: .bold, design: .serif))
                    Text("THE QUIET DEFENDER").font(.system(size: 8, weight: .semibold)).tracking(1.8).foregroundStyle(.white.opacity(0.45))
                }
            }.padding(.top, 42).padding(.bottom, 36)
            ForEach(AppModel.Page.allCases) { page in
                Button { model.page = page } label: {
                    HStack(spacing: 12) {
                        Image(systemName: page.icon).font(.system(size: 15)).frame(width: 20)
                        Text(page.rawValue).font(.system(size: 13, weight: model.page == page ? .semibold : .regular))
                        Spacer()
                        if model.page == page { Circle().fill(Color(red: 0.98, green: 0.49, blue: 0.36)).frame(width: 5, height: 5) }
                    }.padding(.horizontal, 13).frame(height: 43)
                        .background(model.page == page ? Color.white.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(.white.opacity(model.page == page ? 1 : 0.57)).padding(.bottom, 5)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 11) {
                Image(systemName: "sparkle").foregroundStyle(Color(red: 0.94, green: 0.57, blue: 0.43))
                Text("Two local engines.\nOne calm place to scan.").font(.system(size: 12)).lineSpacing(5).foregroundStyle(.white.opacity(0.6))
                Text("OPEN SOURCE · v\(AppVersion.current)").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.3))
            }.padding(12).padding(.bottom, 22)
        }.padding(.horizontal, 18).frame(width: 208).background(Palette.ink).foregroundStyle(.white)
    }
}

struct SectionHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(eyebrow.uppercased()).font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(Palette.red)
            Text(title).font(.system(size: 32, weight: .medium, design: .serif))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.06)))
    }
}

struct PrimaryButton: View {
    var title: String
    var icon: String = "arrow.right"
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(title)
                Image(systemName: icon)
            }.font(.system(size: 12, weight: .semibold)).padding(.horizontal, 18).frame(height: 39)
                .foregroundStyle(.white).background(Palette.red, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }
}

struct OverviewView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 19).fill(Color(red: 0.96, green: 0.93, blue: 0.87))
                if let url = Bundle.main.url(forResource: "mars-guardian", withExtension: "png"), let image = NSImage(contentsOf: url) {
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Image(nsImage: image).resizable().scaledToFit()
                                .frame(width: geo.size.height * 1.777, height: geo.size.height)
                        }.frame(width: geo.size.width, height: geo.size.height).clipped()
                    }.clipShape(RoundedRectangle(cornerRadius: 19))
                }
                LinearGradient(colors: [Color(red: 0.97, green: 0.95, blue: 0.90), Color(red: 0.97, green: 0.95, blue: 0.90).opacity(0.90), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 19))
                VStack(alignment: .leading, spacing: 11) {
                    Text("MEET YOUR QUIET DEFENDER").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(Palette.red)
                    Text("Your Mac.\nUnder your command.").font(.system(size: 30, weight: .medium, design: .serif)).foregroundStyle(Palette.ink)
                    Text("Two local engines.\nA little extra peace of mind.").font(.system(size: 12)).foregroundStyle(Palette.ink.opacity(0.65)).lineSpacing(3)
                    PrimaryButton(title: model.installed ? "Start a scan" : "Set up Mars", icon: "arrow.right") {
                        if model.installed { model.page = .scan } else { model.install() }
                    }.disabled(model.busy).padding(.top, 5)
                }.padding(26)
            }.frame(height: 260)
            HStack(spacing: 14) {
                statusCard(icon: "cpu", title: "CLAMAV ENGINE", value: model.installed ? "Ready to serve" : "Not installed", detail: model.installed ? "Runs locally on your Mac" : "One guided setup", good: model.installed)
                statusCard(icon: "arrow.triangle.2.circlepath", title: "DEFINITIONS", value: model.hasDefinitions ? (model.definitionsStale ? "Update recommended" : "Downloaded") : "Awaiting setup", detail: model.freshness, good: model.hasDefinitions && !model.definitionsStale)
                statusCard(icon: "calendar", title: "NEXT ROUTINE", value: model.savedPreferences.scheduleEnabled ? "On the calendar" : "Your call", detail: model.scheduleSummary, good: model.savedPreferences.scheduleEnabled)
            }
            HStack {
                Text("Your next move").font(.system(size: 21, weight: .medium, design: .serif))
                Spacer()
                Text("NO REAL-TIME MONITORING").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
            }
            Card {
                HStack(spacing: 18) {
                    Image(systemName: model.latest == nil ? "viewfinder" : "checkmark.shield").font(.system(size: 28)).foregroundStyle(Palette.red)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(model.latest?.displayTitle ?? "Every good defense starts with a scan.").font(.system(size: 15, weight: .semibold))
                        if let latest = model.latest {
                            Text("\(latest.scannedFiles.formatted()) files · \(latest.started.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                            Text("A scan result is not a guarantee that your Mac is safe.").font(.system(size: 11)).foregroundStyle(.secondary)
                        } else {
                            Text("Choose a folder, your home, or the entire startup disk.\nNothing gets deleted. You stay in control.")
                                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                        }
                    }
                    Spacer()
                    Button(model.latest == nil ? "Choose a scan" : "View report") {
                        if let latest = model.latest { model.selectedRecord = latest } else { model.page = .scan }
                    }.buttonStyle(.bordered)
                }
            }
            HStack(spacing: 20) {
                Label("No account", systemImage: "person.crop.circle.badge.checkmark")
                Label("No file uploads", systemImage: "externaldrive")
                Label("Open source", systemImage: "curlybraces")
            }.font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
    func statusCard(icon: String, title: String, value: String, detail: String, good: Bool) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon).font(.system(size: 17)).foregroundStyle(good ? Palette.green : .secondary)
                    Spacer()
                    Circle().fill(good ? Palette.green : Color.secondary.opacity(0.3)).frame(width: 5, height: 5)
                }
                Text(title).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                Text(value).font(.system(size: 14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ScopePicker: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 10) {
            ForEach(ScanScope.allCases, id: \.self) { scope in
                Button {
                    model.preferences.scope = scope
                    if scope == .folders && model.preferences.folders.isEmpty { model.chooseFolders() }
                } label: {
                    HStack(spacing: 15) {
                        Image(systemName: scope == .mac ? "desktopcomputer" : (scope == .home ? "house" : "folder"))
                            .font(.system(size: 22)).frame(width: 35).foregroundStyle(model.preferences.scope == scope ? Palette.red : .secondary)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(scope.title).font(.system(size: 14, weight: .semibold))
                            Text(scope == .mac ? "Startup disk, including system and user folders" : (scope == .home ? "Documents, downloads, and everything in your home" : "Only the locations you choose"))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: model.preferences.scope == scope ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 19)).foregroundStyle(model.preferences.scope == scope ? Palette.red : Color.secondary.opacity(0.4))
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(model.preferences.scope == scope ? Palette.red.opacity(0.045) : Palette.card, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(model.preferences.scope == scope ? Palette.red.opacity(0.6) : Color.primary.opacity(0.08)))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if model.preferences.scope == .folders {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.preferences.folders, id: \.self) { folder in
                            HStack {
                                Image(systemName: "folder")
                                Text(folder).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                Spacer()
                                Button { model.preferences.folders.removeAll { $0 == folder } } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                            }
                        }
                        Button("Choose folders…") { model.chooseFolders() }.buttonStyle(.bordered)
                    }
                }
            }
        }.disabled(model.busy)
    }
}

struct ScanView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            SectionHeading(eyebrow: "The defense is yours", title: model.busy ? "A clearer view of your scan." : "A scan, on your terms.", subtitle: "Local engines. Understandable results. Your files stay untouched.")
            if model.busy {
                ScanJourneyView()
            } else {
            ScopePicker()
            HStack {
                Label(model.preferences.yaraXEnabled == true ? "ClamAV + YARA-X requested" : "ClamAV baseline", systemImage: "cpu")
                Text("· \(model.sources.filter { $0.enabled && ($0.engine == .clamav || model.preferences.yaraXEnabled == true) }.count) optional sources requested")
                Spacer()
                Button("Manage engines & sources") { model.page = .sources }
            }.font(.system(size: 11)).foregroundStyle(.secondary)
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Update definitions before scanning", isOn: $model.preferences.updateBeforeScan)
                        .font(.system(size: 13)).disabled(model.busy)
                    Text("Recommended. If the update fails, the scan stops rather than silently using old definitions.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Divider()
                    HStack {
                        if model.busy {
                            ProgressView().controlSize(.small)
                            Text(model.operation).font(.system(size: 12))
                            Spacer()
                            Button("Stop safely") { model.cancel() }
                        } else {
                            Text(model.installed ? "No deletion. No quarantine. Just a clear report." : "Install the engine to begin.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            Spacer()
                            PrimaryButton(title: model.installed ? "Scan now" : "Install ClamAV", icon: "viewfinder") {
                                if model.installed { model.saveScanPreferences(); model.startScan() } else { model.install() }
                            }
                        }
                    }
                }
            }
            Label {
                Text("Entire Mac excludes external volumes and runtime mounts. Protected locations need Full Disk Access; engine limits and unreadable files can reduce coverage. macOS may present folder-access prompts.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            } icon: { Image(systemName: "info.circle").foregroundStyle(.secondary) }
            }
        }
    }
}

struct ScheduleView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            SectionHeading(eyebrow: "A steady routine", title: "Set it. Stay in command.", subtitle: "Daily or weekly scans, run by macOS even when the Mars window is closed.")
            HStack {
                Label(model.scheduleSummary, systemImage: "calendar.badge.clock")
                Spacer()
                if model.preferences != model.savedPreferences { Text("Unsaved changes").foregroundStyle(Palette.red) }
            }.font(.system(size: 11)).foregroundStyle(.secondary)
            Card {
                VStack(alignment: .leading, spacing: 20) {
                    Toggle("Enable scheduled scans", isOn: $model.preferences.scheduleEnabled).font(.system(size: 15, weight: .semibold))
                    Divider()
                    HStack(spacing: 20) {
                        Picker("Repeat", selection: $model.preferences.weekly) {
                            Text("Daily").tag(false); Text("Weekly").tag(true)
                        }.frame(width: 180)
                        if model.preferences.weekly {
                            Picker("On", selection: $model.preferences.weekday) {
                                ForEach(Array(["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"].enumerated()), id: \.offset) { index, day in Text(day).tag(index) }
                            }.frame(width: 185)
                        }
                    }
                    HStack(spacing: 15) {
                        Picker("Hour", selection: $model.preferences.hour) {
                            ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }.frame(width: 120)
                        Picker("Minute", selection: $model.preferences.minute) {
                            ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }.frame(width: 120)
                        Text("Local time · 24-hour clock").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            Text("What should Mars scan?").font(.system(size: 17, weight: .medium, design: .serif))
            ScopePicker()
            Card {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Update definitions before each scan", isOn: $model.preferences.updateBeforeScan)
                    HStack {
                        Text("Shared with your manual scan preferences.").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        PrimaryButton(title: "Save schedule", icon: "checkmark") { model.saveSchedule() }.disabled(model.busy || (model.preferences.scheduleEnabled && !model.installed))
                    }
                }
            }
            Text("Keep Mars.app in Applications and save the schedule again if you move it. You must be logged in. Mars does not wake your Mac; macOS may run a missed interval after wake. Access permissions for the background helper may differ from the app. Results appear in History; no notification permission is required.")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            SectionHeading(eyebrow: "A clear record", title: "Nothing swept under the rug.", subtitle: "Manual and scheduled reports, stored only on this Mac. The latest 200 scans are retained.")
            if model.history.isEmpty {
                Card {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 38)).foregroundStyle(.secondary)
                        Text("Your first report belongs here.").font(.system(size: 19, design: .serif))
                        Text("Run a scan to see detections, warnings, and coverage.").font(.system(size: 12)).foregroundStyle(.secondary)
                        Button("Choose a scan") { model.page = .scan }
                    }.frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            } else {
                ForEach(model.history) { record in
                    Button { model.selectedRecord = record } label: {
                        Card {
                            HStack(spacing: 16) {
                                Image(systemName: record.outcome == .completed ? "checkmark.shield" : "exclamationmark.shield")
                                    .font(.system(size: 25)).foregroundStyle(record.outcome == .completed ? Palette.green : Palette.red)
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(record.displayTitle).font(.system(size: 14, weight: .semibold))
                                    Text("\(record.scope.title) · \(record.scannedFiles.formatted()) files · \(record.scheduled ? "Scheduled" : "Manual")")
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 7) {
                                    Text(record.started.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(.secondary)
                                    Text("\(record.findings.count) detections · \(record.warnings) warnings").font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            SectionHeading(eyebrow: "Behind the shield", title: "Simple, not mysterious.", subtitle: "Your engine, definitions, and permissions. No hidden services. No account.")
            AppUpdatesView()
            Card {
                VStack(alignment: .leading, spacing: 17) {
                    Label("ClamAV engine", systemImage: "cpu").font(.system(size: 15, weight: .semibold))
                    Text(model.installed ? "Installed through Homebrew. Mars uses clamscan and freshclam as separate command-line processes." : "ClamAV is not installed. Mars can install it through Homebrew, then download the official virus definitions.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                    HStack {
                        Button(model.installed ? "Refresh engine status" : "Install ClamAV…") {
                            if model.installed { model.refresh() } else { model.install() }
                        }
                        if model.installed { Button("Update official definitions") { model.updateDefinitions() } }
                    }.disabled(model.busy)
                    Text("Definition database: \(model.freshness)").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("To upgrade the engine itself, use brew upgrade clamav in Terminal. Mars does not run a system-wide ClamAV daemon.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if !model.activeSourceSetupIssues.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("An optional source needs setup", systemImage: "info.circle").font(.system(size: 14, weight: .semibold))
                        Text("This does not block official ClamAV definition updates. Scans will run the baseline and report any skipped optional checks.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Button("Review detection sources") { model.page = .sources }
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Full Disk Access", systemImage: "hand.raised").font(.system(size: 15, weight: .semibold))
                    Text("For the widest coverage, add Mars in System Settings → Privacy & Security → Full Disk Access. Add the mars-scan helper too if scheduled scans report denied access. Find it inside Mars.app → Show Package Contents → Contents → MacOS. This does not override every macOS protection.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                    Button("Open Privacy & Security") { model.open("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 15) {
                    Label("Local by design", systemImage: "externaldrive").font(.system(size: 15, weight: .semibold))
                    Text("Reports contain file paths and detection names. Logs can contain sensitive filenames. Files are never uploaded by Mars. Homebrew and freshclam contact their own distribution services; you can inspect everything in the source.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                    HStack {
                        Button("Open local data") {
                            do { try model.storage.prepare(); NSWorkspace.shared.open(model.storage.root) }
                            catch { model.error = error.localizedDescription }
                        }
                        Button("Source & app releases") { model.open("https://github.com/paulfxyz/mars") }
                    }
                }
            }
            Text("Mars \(AppVersion.current) · MIT app; third-party rules have separate licenses\nIndependent from Apple and the engine providers. No real-time protection, automatic removal, or guarantee of detection.")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(5)
        }
    }
}

struct ActivityView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScanJourneyView()
    }
}

struct RecordView: View {
    let record: ScanRecord
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        ScanResultsView(record: record)
    }
}
