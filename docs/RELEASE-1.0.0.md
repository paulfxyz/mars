# Mars 1.0.0

> Known issue, fixed in [Mars 1.1.0](https://github.com/paulfxyz/mars/releases/tag/v1.1.0): accepting SecuriteInfo terms could enable an unconfigured optional subscription and stop scans and Settings updates. Upgrade to 1.1.0; no subscription is required for the official ClamAV baseline.

Two local engines, selectable detection sources, and a friendlier scan experience. The app remains native, non-destructive, and independent of the engine and feed providers.

## New in 1.0.0

- ClamAV baseline scanning plus optional YARA-X analysis, run sequentially with engine/source attribution.
- Detection Sources screen: official ClamAV, a pinned four-file Elastic Mac starter pack, GPG-verified Sanesecurity malware hashes, user-owned SecuriteInfo feed configuration, and imports for both engines.
- Staged updates, engine validation, retained previous copies, and source rollback.
- Plain-language scan stages, observed counts, elapsed time, safe stopping, and an expandable read-only terminal console.
- Results interpretation, source-by-source coverage, recommended next steps, Finder reveal, copy path, report export, and explicit preparation of another scan.
- Backward-compatible reading of 0.1 reports and preferences.

## Install

Download `Mars-1.0.0-macOS-universal.zip`, verify it with `SHA256SUMS.txt`, extract it, and move Mars.app to Applications. ClamAV is the baseline; install YARA-X and enable a compatible source in Detection Sources to use two engines.

Apple silicon and Intel app slices are included for macOS 13+. The current optional Homebrew YARA-X/GnuPG packages have their own OS and architecture support; availability on an older or Intel Mac is not guaranteed. Unsupported optional installation fails visibly rather than substituting another engine.

## Important boundaries

The app is ad-hoc signed, not Developer ID signed or notarized. Version 1.0.0 is a product version, not a claim of a security audit, certified detection coverage, or real-time protection.

Unofficial feeds are opt-in and retain their own licenses. Elastic's four reviewed files are pinned to a specific revision, not automatically advanced to upstream main. Local imports do not update themselves. SecuriteInfo requires your own authorized download URLs; no account, key, or paid feed is bundled. Sanesecurity requires GnuPG and rsync connectivity, and fails closed on a verification failure.

YARA-X is an additional raw-file rule engine, not an archive-unpacking antivirus replacement. Mars limits its candidate files to 32 MiB and 500,000 per scan; exclusions and access issues appear in coverage notes. Counts from multiple passes are not added together as unique files.

Neither a rule match nor “no detections” is an absolute malware verdict. Mars never removes files or uploads samples. Full Disk Access, Gatekeeper approval, real user-Mac scheduling, and live subscription/mirror acceptance still require hands-on testing; see [validation notes](https://github.com/paulfxyz/mars/blob/main/docs/VALIDATION.md).
