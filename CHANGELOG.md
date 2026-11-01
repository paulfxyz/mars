# Changelog

## 1.1.0

User-reported scan/Settings fix and an in-app update function.

- Prevented an enabled, unconfigured SecuriteInfo source from aborting baseline scans and official definition updates.
- Separated provider terms acceptance, configuration, validation, and activation; retained safe handling for legacy 1.0.0 profiles.
- Made optional update failures explicit skipped checks, with baseline results preserved and accurately labeled.
- Corrected first-update source metadata refresh and promoted failure explanations into the readable report.
- Added manual stable-release checks, numeric version comparison, official-repository asset restrictions, SHA-256 verified downloads, and preserved macOS quarantine metadata.
- Added deterministic official-refresh seams plus real native scans to cover the default pre-scan update path without downloading an entire official database on every CI run.

## 1.0.0

Two-engine and multi-source release, with clearer during-scan and after-scan guidance.

- Optional YARA-X engine alongside the ClamAV baseline, with sequential source-specific passes and exact finding provenance.
- Detection Sources manager, consent gates, a pinned Elastic Mac starter pack, GPG-verified Sanesecurity hashes, private SecuriteInfo feed URLs, and validated local imports for both engines.
- Staged source activation, retained previous versions, and rollback under the shared operation lock.
- Bounded verbose terminal relay, elapsed time, real scan stages, observed counts, and plain-language explanations.
- Beginner-friendly report interpretation, per-source coverage, safe next steps, copy/reveal/export, and explicit rescan preparation.
- Old report/preferences migration, tamper rejection, private-feed isolation, rollback, real dual-engine fixture, and live pinned-pack tests.
- Demo mode now resets preferences to synthetic values before screenshot capture.

Version 1.0.0 does not imply notarization, an external security audit, or real-time endpoint protection. Optional engine availability and source licenses remain separate from the app.

## 0.1.0

Initial community preview of Mars, a native SwiftUI/AppKit interface for ClamAV.

- Guided ClamAV installation through Homebrew and user-confirmed Homebrew bootstrap when needed.
- User-owned official definition database with manual and pre-scan FreshClam updates.
- Startup disk, home, and selected-folder manual scans, with cancellation and live activity.
- Per-user launchd daily/weekly background scans through a bundled helper.
- Local history, warnings, detections, JSON export, and non-destructive Finder reveal.
- Original manga guardian, ivory/charcoal/vermilion visual identity, native shield app icon, and light/dark appearance.
- Universal arm64/x86_64 packaging, ad-hoc signing, checksums, native CI, and harmless real-engine integration tests.

This release has no real-time protection, automatic remediation, automatic app updater, Developer ID signature, or notarization. Actual user-Mac permissions, installation, and unattended scheduling require hands-on acceptance.
