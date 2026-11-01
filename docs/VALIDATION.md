# Mars validation

This document separates automated evidence from real-Mac acceptance. A successful build is not proof of comprehensive antivirus protection.

## Mars 1.1.0 regression coverage

The [native macOS 15 validation run](https://github.com/paulfxyz/mars/actions/runs/41330001643) executed **55 tests: 54 passed, one live provider-connectivity test skipped, zero failures**. It built and architecture-checked the universal app and helper, verified the ad-hoc signature, and captured eleven native views. Tested Swift source is `5489560`; the subsequent documentation and capture refresh does not change that Swift source.

All eleven captures were visually reviewed, including Settings' app-update card and the missing-subscription result. The downloaded ZIP independently passed its SHA-256 manifest check. Sanesecurity's live rsync mirror was unavailable after three transport attempts on this run; no live vendor signature loading is claimed for it. Successful earlier vendor checks remain historical evidence, not proof of present connectivity.

The regression suite reproduces a saved 1.0.0 profile with SecuriteInfo enabled and its private configuration file missing. It exercises both Settings' official-only refresh and the default update-before-scan path. The latter uses a deterministic official-refresh test seam followed by **real clamscan** against harmless local fixtures; it does not pretend that CI downloaded the full official database. The production public initializer does not expose that seam.

Additional checks cover terms acceptance without activation, disabling legacy broken configuration, actionable setup errors, optional-source warning isolation, cancellation, and a first automatic YARA-X source update using fresh metadata.

Updater checks cover numeric versions, stable-release parsing, exact official repository URLs, missing/duplicate checksums, tamper rejection, cancellation, and a live published-release download with SHA-256 verification and macOS quarantine metadata. They never install or execute the downloaded app.

The live Sanesecurity test permits at most three attempts for provider **transport failures only**. Signature, loading, and assertion failures still fail CI. If transport remains unavailable, the test verifies that nothing was activated and is explicitly marked **skipped**, not passed; the live vendor verification is not established on that run. This acknowledges mirror variability without bypassing integrity checks. macOS 15 is the native runner, replacing the retiring macOS 14 image.

Screenshots use LaunchServices to open the actual packaged app. If the headless CI launch has no initial scene window, the app hosts its exact production `RootView` in a native `NSWindow`; there is no alternative mock interface. Captures reject menu-bar-only windows and require an actual rendered report for result images.

## Historical Mars 1.0.0 build

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
