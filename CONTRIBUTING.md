# Contributing

Mars is deliberately small: a native interface, a testable Foundation core, and a standalone scheduled-scan helper. Contributions should preserve explicit user consent and non-destructive scanning.

## Work locally

Use macOS 13+ and Swift 5.9+. Run `swift test` and `swift build` before opening a pull request. For real-engine fixtures, install the optional components too:

```sh
brew install clamav yara-x
MARS_CLAMAV_TESTS=1 swift test
```

Set `MARS_SOURCE_NETWORK_TESTS=1` as well to exercise the live pinned Elastic download and the app-updater release download. Automatic Sanesecurity downloads and their network tests were removed in 1.1.1; there is no rsync or GnuPG requirement. Mandatory tests cover retirement of saved legacy profiles without deleting their files or history.

The integration fixture uses a harmless custom ASCII signature database. Do not commit malware, real private scan logs, signing credentials, downloaded official databases, or user exports.

## Interface changes

Check light and dark appearances, minimum 1020×740 window size, long folder names, empty history, missing engine, failed definition updates, active/cancelled scans, warnings, and multiple detections. Do not display a protective green state merely because the app is open.

Use `dist/Mars.app/Contents/MacOS/mars --demo` for synthetic visual review after packaging. Demo mode must never execute engine operations or persist its synthetic history. Capture screenshots from the running app; label all synthetic data.

## Release

Set the version in `scripts/package.sh` and `AppVersion.fallback` for unbundled development. The packaged About panel and Settings read Info.plist; the release workflow derives its tag and filenames from the packaging version. Keep README, changelog, and release notes synchronized.

Run the native CI suite, verify both binary architectures and signatures, inspect screenshots, and download the generated archive to check its SHA-256 checksum. GitHub's [macOS 14 retirement notice](https://github.com/actions/runner-images/issues/13518) schedules full retirement for November 2, 2026; current validation therefore uses macOS 15 rather than a brownout-affected image.

Regression scenarios must include legacy enabled-but-unconfigured optional sources, default update-before-scan behavior, official-only Settings updates, first-use source activation, and failure explanations. The deterministic official-refresh seam is internal to tests; actual clamscan/YARA-X fixtures still run on native macOS. Live app-update tests download an official release, verify its checksum, and inspect quarantine metadata without extracting or executing it.

Do not replace published release assets in place. Releases must clearly disclose missing notarization, unaudited status, and hands-on permissions, real installation, sleep/wake scheduling, and detection acceptance limits; a 1.0 version number does not remove those limits.
