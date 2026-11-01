# Privacy

Mars has no accounts, analytics, telemetry SDK, hosted backend, advertising, or project-operated upload service. It passes paths to a separately installed ClamAV scanner and retains results locally.

## Stored on your Mac

`~/Library/Application Support/mars/` holds preferences, folder paths, downloaded definitions, FreshClam configuration, operation lock, reports, and logs. Reports contain paths, signature names, timestamps, coverage counts, engine status, and scope. Logs can expose filenames and other sensitive local details. The directory is created with user-only permissions.

The latest 200 scan reports are retained. Associated expired raw scan logs are removed, and each raw log is capped at approximately 32 MiB. Install and definition-update logs are overwritten on their next run. LaunchAgent diagnostic logs are not automatically rotated. Deleting local data also deletes the downloaded databases and preferences; disable the schedule before removing that directory.

JSON export contains no credentials because Mars does not collect any, but can contain sensitive file paths. Exports are written only to a location you select.

## Network activity

Homebrew installs engine software and dependencies from its own infrastructure. FreshClam downloads official signatures using its configured mirror and DNS discovery. These services see normal connection metadata, such as your public IP address; their policies apply. The [official signature-management documentation](https://docs.clamav.net/manual/Usage/SignatureManagement.html) explains FreshClam's role.

The optional Homebrew installer downloads a script from Homebrew's official GitHub repository and runs it in a visible Terminal only after you confirm. Documentation and source buttons open external websites in your browser. Mars does not automatically check GitHub for app updates.

Mars does not pass scanned file contents to a cloud scanner or submit samples. It does not enable optional ClamAV sample-submission features.

## Additional engines and sources in 1.0.0

YARA-X also scans locally; no sample upload or VirusTotal API integration is enabled. Optional Elastic updates contact raw.githubusercontent.com for pinned files and their license. Sanesecurity uses its rsync mirror and a pinned GPG public key. SecuriteInfo uses official HTTPS URLs supplied by your own authorized account.

Private subscription URLs live in `private-securiteinfo-urls.txt` with 0600 permissions inside the user-only data directory, not Keychain. They are omitted from source metadata, reports, exports, and displayed logs. Downloads use short-lived 0600 curl configuration files rather than placing private URLs in process arguments. A process with the same user privileges can still read local files; the storage is access-restricted, not encrypted.

Optional source directories retain an active and previous version, plus license information where supplied. Imported packs are copied locally after validation. They do not update automatically; no rules or paid feeds are submitted to the Mars repository.

## Permissions

Mars runs as your user. Full Disk Access is optional and user-granted; it is not secretly enabled. Terminal handles any Homebrew administrator prompt, and Mars does not read the password. Background scans use a per-user LaunchAgent and may need separate access approval.
