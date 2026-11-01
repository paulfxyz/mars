# Mars validation

This document separates automated evidence from real-Mac acceptance. A successful build is not proof of comprehensive antivirus protection.

## Mars 1.0.0 verified build

The [native macOS run on November 1, 2026](https://github.com/paulfxyz/mars/actions/runs/41312796415) passed **36 tests with zero failures**, packaged the universal app, verified its ad-hoc signature and both architectures, and captured ten actual native views. Its tested app-source commit is `e662105`; the following documentation and screenshot additions do not change that app source.

The checks include old-report/preferences migration, opt-in source defaults, pinned-content tamper rejection, private URL restrictions/storage permissions, activation and rollback, YARA JSON attribution, candidate-list limits, user cancellation, a bounded transport deadline that is not mislabeled user cancellation, safe result interpretation, and an isolated pinned GPG verification keyring.

Live tests downloaded and compiled the pinned Elastic Mac pack, and downloaded Sanesecurity's four files, verified their detached signatures against the embedded provider key, and loaded them in ClamAV. A harmless custom fixture exercised ClamAV and YARA-X in the same scan and preserved engine/source provenance. No real malware was used.

The downloaded universal ZIP passed a second SHA-256 check outside the CI runner. All ten captures were visually reviewed: overview, scan setup, schedule, history, settings, dark overview, compact overview, sources, during-scan console, and the actual results sheet. All use clearly labeled synthetic data; scrollable screens intentionally show a normal viewport rather than fabricated full-page layouts.

## Historical 0.1.0 evidence

The [native macOS run on October 31, 2026](https://github.com/paulfxyz/mars/actions/runs/41188889071) passed **17 tests with zero failures**, including the real ClamAV custom-signature fixture. The tested app-source commit is `3cb0f8c`; subsequent repository documentation and image additions do not change the app source in this release.

The run built both arm64 and x86_64, combined and checked the architectures of both executables, verified the ad-hoc bundle signature, and produced the release ZIP. Its downloaded ZIP passed a second SHA-256 check outside the CI runner.

Seven actual native captures were visually reviewed: overview, scan, schedule, history, settings, dark overview, and compact overview. They are available in [the screenshot gallery](SCREENSHOTS.md) and use explicitly labeled synthetic data. The overview fits the default window, the compact view remains scrollable, and longer schedule/settings screens scroll normally.

## Automated gates

The macOS CI workflow must pass all unit tests, including parsing detections with colon/Unicode paths, warnings and incomplete results, cancellation, pre-cancelled operations, direct argument construction, local storage, corrupt-data fallback, shared-operation locking, configuration generation, daily/weekly launchd dictionaries, and harmless custom-signature ClamAV detection and no-detection fixtures.

Packaging must build both arm64 and x86_64 executables for GUI and helper, verify the universal binaries, pass `codesign --verify --deep --strict`, produce a ZIP plus checksum, and capture an actual native interface in demo mode. Demo data is clearly labeled.

## Not yet established by automation

- Homebrew's interactive first-install flow on a fresh personal Mac.
- User approval of an unnotarized download under local or managed Gatekeeper policy.
- Full Disk Access for both GUI and LaunchAgent helper on each supported macOS release.
- A complete user-approved startup-disk scan with a review of skipped/unreadable files.
- A real scheduled run while the GUI is quit, followed by sleep/wake and login behavior.
- Real-world malware detection performance, false-positive rate, or resistance to hostile input.
- Native Intel execution; a universal Intel slice is built and checked but not executed by an Apple-silicon runner.
- A real paid SecuriteInfo account and authorized subscription URLs; configuration validation is tested, not a customer's account.
- Optional Homebrew YARA-X/GnuPG/rsync availability on every macOS 13+ and Intel configuration.
- Detection quality of arbitrary imported packs or all upstream Elastic rules beyond the four pinned files.

## Hands-on acceptance checklist

Install the downloaded app in Applications, approve opening through normal macOS controls, install the engine, download definitions, run a small known folder, cancel another scan, and inspect the report. Then grant intended access and run a broader scan, reviewing warnings rather than just the headline.

Save a near-future schedule, quit the GUI, remain logged in and awake, and verify a new scheduled report appears. Repeat across sleep/wake and after replacing the app. Confirm permissions for the helper rather than inferring them from the GUI.
