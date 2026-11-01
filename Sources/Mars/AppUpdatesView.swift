import SwiftUI
import AppKit
import MarsCore

struct AppUpdatesView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Mars app updates", systemImage: "arrow.down.app").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("Installed \(AppVersion.current)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text(model.appUpdateMessage).font(.system(size: 12)).foregroundStyle(.secondary)
                if let error = model.appUpdateError {
                    Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(Palette.red)
                }
                HStack {
                    if model.appUpdateBusy {
                        ProgressView().controlSize(.small)
                        Button("Cancel update check/download") { model.cancelAppUpdate() }
                    } else {
                        Button("Check for app updates") { model.checkAppUpdates() }
                        if model.availableAppRelease != nil && model.verifiedAppDownload == nil {
                            Button("Download & verify update") { model.downloadAppUpdate() }
                        }
                        if let file = model.verifiedAppDownload {
                            Button("Reveal verified update in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                        }
                    }
                    Spacer()
                    Button("Release notes") { model.open(model.availableAppRelease?.page.absoluteString ?? "https://github.com/paulfxyz/mars/releases") }
                }.font(.system(size: 11))
                Text(model.verifiedAppDownload == nil
                    ? "Checks are manual. Updates come only from this project's GitHub releases. SHA-256 verifies download integrity, not an Apple developer signature. No automatic installation or surprise app restart."
                    : "To install: finish any scan, quit Mars, extract the verified ZIP, and replace Mars.app in Applications. Open the new app, then save your schedule again if you use background scans. Your existing preferences, sources, and reports are retained.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            }
        }
    }
}
