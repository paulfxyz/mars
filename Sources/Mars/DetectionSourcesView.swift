import SwiftUI
import AppKit
import MarsCore

struct DetectionSourcesView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionHeading(eyebrow: "Choose your detection layers", title: "Two engines. Clear origins.",
                subtitle: "ClamAV is the baseline. YARA-X adds optional local pattern checks. More rules can also mean more noise; each source stays visible and under your control.")
            HStack(alignment: .top, spacing: 14) {
                Card {
                    VStack(alignment: .leading, spacing: 13) {
                        Label("ClamAV", systemImage: "shield").font(.system(size: 18, weight: .semibold))
                        Text("Baseline engine · official definitions").font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(model.installed ? "Installed" : "Setup required").font(.system(size: 13, weight: .medium))
                        Button(model.installed ? "Update all enabled sources" : "Install ClamAV…") {
                            if model.installed { model.updateDefinitions() } else { model.install() }
                        }.disabled(model.busy)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 13) {
                        Label("YARA-X", systemImage: "sparkle.magnifyingglass").font(.system(size: 18, weight: .semibold))
                        Text("Optional rule-matching engine · BSD-3-Clause").font(.system(size: 11)).foregroundStyle(.secondary)
                        Toggle("Include YARA-X in scans", isOn: Binding(get: { model.preferences.yaraXEnabled == true }, set: {
                            model.preferences.yaraXEnabled = $0; model.saveScanPreferences()
                        })).disabled(model.busy)
                        if !model.yaraXInstalled {
                            Button("Install YARA-X…") { model.optionalPackage = "yara-x" }.disabled(model.busy)
                        } else {
                            Text("Installed · enable at least one YARA-X source below").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Card {
                HStack {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Official ClamAV definitions", systemImage: "checkmark.seal").font(.system(size: 14, weight: .semibold))
                        Text("Always used by the baseline scan · FreshClam update: \(model.freshness)").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("DEFAULT").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(Palette.green)
                }
            }
            ForEach(model.sources) { source in
                Card {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(source.name).font(.system(size: 15, weight: .semibold))
                                Text("\(source.engine.rawValue) · \(source.files) definition/rule files").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("Enabled", isOn: Binding(get: { source.enabled }, set: { _ in model.enableSource(source) }))
                                .labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(model.busy)
                                .accessibilityLabel("Enable \(source.name)")
                        }
                        Text(source.explanation).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                        Text(source.license).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        HStack {
                            Text(source.updated.map { "Last successful update: \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Not yet downloaded or configured")
                            Spacer()
                            if source.enabled && source.engine == .yaraX && model.preferences.yaraXEnabled != true { Text("YARA-X scan is off").foregroundStyle(Palette.red) }
                        }.font(.system(size: 10)).foregroundStyle(.secondary)
                        if let revision = source.revision { Text(revision).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled) }
                        if let error = source.lastError { Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(Palette.red) }
                        HStack {
                            if source.kind != .local {
                                Button("Update & validate") { model.updateSource(source) }.disabled(!source.acceptedTerms || model.busy)
                            }
                            if source.kind == .securiteinfo { Button("Configure private feed URLs…") { model.showPrivateFeedSetup = true }.disabled(model.busy) }
                            if source.kind == .sanesecurity { Button("Install verification tools…") { model.optionalPackage = "gnupg" }.disabled(model.busy) }
                            Button("Roll back") { model.rollbackSource(source) }
                                .disabled(model.busy || !FileManager.default.fileExists(atPath: model.storage.sourceDirectory(source.id).appendingPathComponent("previous").path))
                            Spacer()
                            if source.kind != .local { Button("Provider & terms") { model.open(source.origin) } }
                        }.font(.system(size: 11))
                    }
                }
            }
            HStack {
                Button("Import ClamAV definitions / compatible YARA…") { model.importSource(engine: .clamav) }
                Button("Import YARA-X rules…") { model.importSource(engine: .yaraX) }
            }.disabled(model.busy)
            Text("Updates are staged, checked by the target engine, then activated under the shared scan lock. Elastic files additionally require pinned hashes; Sanesecurity requires its pinned GPG key. One prior copy is retained for rollback. Local imports do not update themselves. No rule count is a claim of detection quality.")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
        }
    }
}

struct SourceConsentView: View {
    let source: DetectionSource
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            Text("Enable \(source.name)?").font(.system(size: 25, weight: .medium, design: .serif))
            Text(source.explanation).font(.system(size: 13)).lineSpacing(5)
            Text("License: \(source.license)").font(.system(size: 12, weight: .medium))
            Text("These are not Mars-owned MIT definitions. Review the provider's current terms and confirm you have the rights to use them. A successful signature check or compilation establishes authenticity/format, not detection accuracy. Unofficial sources may produce false positives.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
            if source.kind == .elastic {
                Text("This source downloads only the four files pinned in this release; it does not automatically track upstream main. A reviewed Mars update is needed to advance the pinned revision.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack {
                Button("Read provider terms") { model.open(source.kind == .elastic ? "https://github.com/elastic/protections-artifacts/blob/main/LICENSE.txt" : source.origin) }
                Spacer()
                Button("Cancel") { dismiss() }
                PrimaryButton(title: "I accept · enable", icon: "checkmark") { model.acceptSource(source); dismiss() }
            }
        }.padding(30).frame(width: 620).background(Palette.background)
    }
}

struct PrivateFeedsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var entry = ""
    @State private var urls: [String] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your SecuriteInfo feed").font(.system(size: 25, weight: .medium, design: .serif))
            Text("Copy signature download URLs from your own licensed account. Add them one at a time; Mars accepts only official HTTPS /get/signatures/ links. Do not share these private links in GitHub issues.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            SecureField("Private signature URL", text: $entry).textFieldStyle(.roundedBorder).privacySensitive()
            HStack {
                Button("Add URL") { if !entry.isEmpty { urls.append(entry); entry = "" } }.disabled(urls.count >= 20 || entry.isEmpty)
                Text("\(urls.count) private URLs entered").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Clear entered URLs") { urls = []; entry = "" }
            }
            Text("Saving replaces the configured URL list. It is stored only in a user-only (0600) file inside Mars's private local data directory, not in Keychain. Temporary transport configuration also uses 0600 permissions. URLs are not shown in process arguments, scan reports, exports, or the console. Other processes with your user privileges can still read your local files.")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                PrimaryButton(title: "Save private configuration", icon: "lock") {
                    var values = urls; if !entry.isEmpty { values.append(entry) }
                    model.savePrivateFeeds(values.joined(separator: "\n"))
                }.disabled(urls.isEmpty && entry.isEmpty)
            }
        }.padding(30).frame(width: 650).background(Palette.background)
            .onDisappear { entry = ""; urls = [] }
    }
}
