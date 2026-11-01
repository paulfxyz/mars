import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--screenshot"), arguments.indices.contains(index + 1) {
            NSApp.appearance = NSAppearance(named: arguments.contains("--dark") ? .darkAqua : .aqua)
            if arguments.contains("--compact") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApp.windows.first(where: { $0.canBecomeMain })?.setContentSize(NSSize(width: 1020, height: 740))
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                let visible = NSApp.windows.filter { $0.isVisible && $0.contentView != nil }
                let chosen = arguments.contains("--results") ? (visible.first(where: { $0.isSheet }) ?? visible.first) : visible.first
                guard let window = chosen,
                      let view = window.contentView,
                      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(3) }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(4) }
                do { try data.write(to: URL(fileURLWithPath: arguments[index + 1])); exit(0) }
                catch { exit(5) }
            }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.busy else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "An engine operation is running."
        alert.informativeText = "Stop the operation before quitting so Mars can save the report."
        alert.addButton(withTitle: "Keep Mars open")
        alert.addButton(withTitle: "Stop operation")
        if alert.runModal() == .alertSecondButtonReturn { model.cancel() }
        return .terminateCancel
    }
}

@main
@MainActor
struct MarsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("Mars", id: "main") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1020, minHeight: 740)
                .onAppear { delegate.model = model }
                .alert("Mars needs your attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                    Button("OK") { model.error = nil }
                } message: { Text(model.error ?? "") }
                .confirmationDialog("Install ClamAV with Homebrew?", isPresented: $model.showInstallConfirmation, titleVisibility: .visible) {
                    Button("Install ClamAV") { model.installConfirmed() }
                } message: { Text("Mars will run brew install clamav, then download official definitions. This installs software and dependencies on your Mac. Your files will not be scanned until you choose Scan.") }
                .alert("Install Homebrew in Terminal?", isPresented: $model.showHomebrewConfirmation) {
                    Button("Open installer") { model.installHomebrew() }
                    Button("Read Homebrew instructions") { model.open("https://brew.sh") }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Homebrew is required to install ClamAV. Mars will open the official Homebrew install script in a visible Terminal window. Review its prompts; it may ask for your administrator password. Mars cannot see the password. Once it finishes, return here and click Install ClamAV again.")
                }
        }
        .defaultSize(width: 1120, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Mars") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationName: "Mars", .applicationVersion: "1.0.0",
                        .credits: NSAttributedString(string: "Your Mac. Two local engines.\nAn independent open-source app by Paul Fleury.\nMIT app · Third-party definitions have separate licenses")
                    ])
                }
            }
            CommandGroup(after: .newItem) {
                Button("Scan now") { model.startScan() }.keyboardShortcut("r").disabled(model.busy || !model.installed)
                Button("Update definitions") { model.updateDefinitions() }.keyboardShortcut("u").disabled(model.busy || !model.installed)
            }
            CommandGroup(replacing: .appTermination) {
                Button("Quit Mars") {
                    if model.busy {
                        let alert = NSAlert()
                        alert.messageText = "An engine operation is running."
                        alert.informativeText = "Stop the operation before quitting. Scheduled scans run independently."
                        alert.addButton(withTitle: "Keep Mars open")
                        alert.addButton(withTitle: "Stop operation")
                        if alert.runModal() == .alertSecondButtonReturn { model.cancel() }
                    } else { NSApp.terminate(nil) }
                }.keyboardShortcut("q")
            }
        }
        MenuBarExtra("Mars", systemImage: "shield.lefthalf.filled") { MarsMenu().environmentObject(model) }
    }
}

struct MarsMenu: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) var openWindow
    var body: some View {
        Text(model.busy ? model.operation : "Mars · On-demand scanning")
        Button("Open Mars") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("Scan now") { model.startScan() }.disabled(model.busy || !model.installed)
        Button("Update definitions") { model.updateDefinitions() }.disabled(model.busy || !model.installed)
        Divider()
        Text(model.scheduleSummary)
        Button("Quit Mars") { NSApp.terminate(nil) }.disabled(model.busy)
    }
}
