# Contributing

Mars is deliberately small: a native interface, a testable Foundation core, and a standalone scheduled-scan helper. Contributions should preserve explicit user consent and non-destructive scanning.

## Work locally

Use macOS 13+ and Swift 5.9+. Run `swift test` and `swift build` before opening a pull request. For the real-engine fixture, install ClamAV through Homebrew and run `MARS_CLAMAV_TESTS=1 swift test`.

The integration fixture uses a harmless custom ASCII signature database. Do not commit malware, real private scan logs, signing credentials, downloaded official databases, or user exports.

## Interface changes

Check light and dark appearances, minimum 1020×740 window size, long folder names, empty history, missing engine, failed definition updates, active/cancelled scans, warnings, and multiple detections. Do not display a protective green state merely because the app is open.

Use `dist/Mars.app/Contents/MacOS/mars --demo` for synthetic visual review after packaging. Demo mode must never execute engine operations or persist its synthetic history. Capture screenshots from the running app; label all synthetic data.

## Release

Increment the app version consistently in the packaging script, About panel, Settings, README, changelog, and release notes. Run the native CI suite, verify both binary architectures and signatures, inspect screenshots, and download the generated archive to check its SHA-256 checksum.

Do not replace published release assets in place. Early releases must remain clearly labeled community previews until hands-on permissions, real installation, sleep/wake scheduling, and detection behavior have been accepted on real Macs.
