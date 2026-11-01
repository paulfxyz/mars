# Contributing

Mars is deliberately small: a native interface, a testable Foundation core, and a standalone scheduled-scan helper. Contributions should preserve explicit user consent and non-destructive scanning.

## Work locally

Use macOS 13+ and Swift 5.9+. Run `swift test` and `swift build` before opening a pull request. For real-engine fixtures, install the optional components too:

```sh
brew install clamav yara-x gnupg rsync
MARS_CLAMAV_TESTS=1 swift test
```

Set `MARS_SOURCE_NETWORK_TESTS=1` as well to exercise the live pinned Elastic download and GPG-verified Sanesecurity mirror update. These tests require the relevant network access; a mirror timeout is a failure, not a skipped or silently accepted source.

The integration fixture uses a harmless custom ASCII signature database. Do not commit malware, real private scan logs, signing credentials, downloaded official databases, or user exports.

## Interface changes

Check light and dark appearances, minimum 1020×740 window size, long folder names, empty history, missing engine, failed definition updates, active/cancelled scans, warnings, and multiple detections. Do not display a protective green state merely because the app is open.

Use `dist/Mars.app/Contents/MacOS/mars --demo` for synthetic visual review after packaging. Demo mode must never execute engine operations or persist its synthetic history. Capture screenshots from the running app; label all synthetic data.

## Release

Increment the app version consistently in the packaging script, About panel, Settings, README, changelog, workflow release target, and release notes. Run the native CI suite, verify both binary architectures and signatures, inspect screenshots, and download the generated archive to check its SHA-256 checksum.

Do not replace published release assets in place. Releases must clearly disclose missing notarization, unaudited status, and hands-on permissions, real installation, sleep/wake scheduling, and detection acceptance limits; a 1.0 version number does not remove those limits.
