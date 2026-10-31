# Mars 0.1.0

A native macOS ClamAV companion, with a little mythology and a serious antivirus engine. This is the first community preview, not a production-certified endpoint security product.

## Included

- Native SwiftUI/AppKit interface and original manga-style Mars guardian.
- Guided ClamAV installation, definition updates, and startup-disk/home/folder scans.
- Daily and weekly LaunchAgent scans that do not require the app window to remain open.
- Local reports, warnings, detections, safe cancellation, and JSON export.
- Universal Apple silicon and Intel app for macOS 13+.

## Download

Extract `Mars-0.1.0-macOS-universal.zip`, move Mars.app into Applications, and open it. Verify with `SHA256SUMS.txt` if desired.

The app is ad-hoc signed, not Developer ID signed or notarized. Use normal macOS approval controls only; do not disable Gatekeeper. Read [INSTALL.md](https://github.com/paulfxyz/mars/blob/main/INSTALL.md) for setup, permissions, scheduling, and removal.

## Boundaries

Mars scans on demand or on a saved schedule. It does not provide real-time monitoring, remove files, quarantine files, or guarantee that a Mac is safe. ClamAV is installed separately using Homebrew, and initial definition downloads require network access.

Automated native tests and a harmless ClamAV integration fixture accompany this release. User-Mac installation, Full Disk Access, unattended scheduling, and broad-disk scan acceptance still need hands-on testing; see [validation notes](https://github.com/paulfxyz/mars/blob/main/docs/VALIDATION.md).
