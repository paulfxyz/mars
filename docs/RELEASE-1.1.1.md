# Mars 1.1.1

Fixes source setup and removes the unreliable automatic Sanesecurity integration.

## SecuriteInfo: configure it before enabling it

- First launch creates an empty `private-securiteinfo-urls.txt` with 0600 permissions in Mars's private local-data directory.
- Existing nonempty configurations are never overwritten by preparation.
- Empty and whitespace-only configurations are ordinary **not configured** states: the source is off, stale missing-file errors disappear, and **Configure sources…** explains the next step.
- Add your own authorized URLs, accept the terms, update and validate, then explicitly enable the source. Replacing URLs resets activation and validation.
- Genuine failures for nonempty invalid configuration remain visible. The official ClamAV baseline does not require a subscription.

## Sanesecurity automatic downloads removed

The rsync integration was unreliable and has been removed rather than masking its transport errors. The card, updater, vendor key, verification-tools installer, and live integration tests are removed. Existing legacy profiles are excluded from scans and update-all, without deleting their downloaded files or historical reports. Trusted definition files can still be imported manually.

ClamAV, optional YARA-X, pinned Elastic Mac rules, local imports, manual app-update checks, and scheduled scans remain available.

## Upgrade

In Mars 1.1.0, use **Settings → Check for app updates**, then download and verify the ZIP. Quit Mars, extract it, and replace Mars.app in Applications. Keep your existing local data; re-save your schedule if you use background scans. Installation remains manual, and the community app remains ad-hoc signed and unnotarized.

Native validation and its limits are recorded in the [validation notes](https://github.com/paulfxyz/mars/blob/main/docs/VALIDATION.md). Hands-on scanning, permissions, and scheduling on your own Mac still require acceptance.
