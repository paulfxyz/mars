# Mars 1.1.0

Fixes the scan and Settings failure caused by an enabled but unconfigured SecuriteInfo source. Adds manual in-app update checks and integrity-verified downloads.

## Fixed

- Optional subscription configuration can no longer block the official ClamAV baseline scan.
- Settings and menu definition updates refresh official ClamAV definitions only. Update all enabled sources is a separate explicit action; optional failures are warnings, not failures of the successful official refresh.
- Accepting provider terms does not enable a source. Configuration, successful validation, and activation are separate steps.
- Existing 1.0.0 profiles with enabled/missing subscription configuration are handled without deleting preferences, sources, or reports. The baseline runs; the unavailable source is identified as skipped.
- A newly downloaded source is checked against its fresh metadata, not the stale pre-update snapshot.
- Failure explanations are visible in the main report, and completed baseline scans with missing optional checks receive a distinct title.

## App updates

Use Settings → Mars app updates or the app menu's Check for app updates command. Mars checks the official stable GitHub release, compares numeric versions, and offers a download only when newer.

Downloads must come from the expected project release URLs and pass the exact archive's SHA-256 checksum. The ZIP retains macOS quarantine metadata; nothing is automatically extracted, executed, installed, or restarted. Use Reveal verified update in Finder, finish any scan, quit Mars, extract the ZIP, and replace Mars.app in Applications.

The checksum verifies integrity, not Apple Developer ID identity. The app remains ad-hoc signed and unnotarized; this is not an automatic installer or a replacement for normal macOS approval.

## Install this version

Download `Mars-1.1.0-macOS-universal.zip`, extract it, and replace the older Mars.app after quitting it. Existing local data is retained. If you use scheduled scans, open the new app and save the schedule again.

SecuriteInfo is optional and still requires your own authorized feed URLs. If you do not use that subscription, leave it disabled. ClamAV does not require it.
