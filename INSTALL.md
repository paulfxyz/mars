# Install Mars

Mars is a native macOS 13+ app for Apple silicon and Intel Macs. The first version is a community preview; its ad-hoc signature provides bundle integrity, not a verified Apple developer identity.

## Download and open

Download the universal ZIP and SHA256SUMS.txt from [GitHub Releases](https://github.com/paulfxyz/mars/releases). To verify the download before opening:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

Keep the checksum next to the ZIP. Extract the archive, move Mars.app to Applications, then open it. If macOS blocks an unidentified developer, review the warning and use the approval offered by System Settings → Privacy & Security only if you trust the download. Organizational policy can prevent opening it. Do not disable Gatekeeper, SIP, quarantine checks globally, or managed security policies.

## Install ClamAV

Choose Set up Mars and confirm installation. Mars runs `brew install clamav`, followed by FreshClam to download the official definitions, using the [documented Homebrew installation route](https://docs.clamav.net/manual/Installing/Packages.html).

If Homebrew is absent, Mars asks before opening the official Homebrew installation command in Terminal. Terminal may ask for administrator privileges or Command Line Tools installation; those prompts belong to Homebrew and macOS. Review them yourself. Mars does not collect or store administrator passwords.

The visible command is:

```sh
/bin/bash -c "$(/usr/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

You may instead install Homebrew yourself from [brew.sh](https://brew.sh). When finished, return to Mars and choose Install ClamAV again. Mars checks `/opt/homebrew` and `/usr/local` and uses its own database under `~/Library/Application Support/mars/Database`.

The first definition download can be substantial. The live activity panel shows output; do not repeatedly retry a mirror error. ClamAV's documentation describes [FreshClam troubleshooting and rate limits](https://docs.clamav.net/faq/faq-freshclam.html).

## Permissions and scan scope

Choose your home, selected folders, or Entire Mac. Full Disk Access can be granted in System Settings → Privacy & Security → Full Disk Access by adding Mars.app. Quit and reopen Mars after changing permissions if macOS requests it.

Entire Mac scans the startup disk at `/`. It excludes external volumes under `/Volumes`, `/dev`, and selected runtime mounts. System mount aliases can cause duplicate inspection. ClamAV does not follow symbolic links and retains its default scanning limits. A warning or unreadable location means reduced coverage, even if no threat was detected.

To scan an external volume, choose Selected folders and select it explicitly. If a disk is not mounted, the scan fails rather than silently scanning an empty replacement location.

## Scheduled scans

Install Mars.app in Applications before enabling a schedule. In Schedule, choose daily or weekly, set local hour and minute, choose the scope, then Save schedule. Changes are not activated until you save.

Mars writes only its own LaunchAgent:

```text
~/Library/LaunchAgents/com.paulfleury.mars.scan.plist
```

The job runs `Mars.app/Contents/MacOS/mars-scan`. It works with the GUI quit but requires your logged-in user session. Mars does not wake the Mac, keep it awake, or run scans before login. launchd may coalesce missed calendar events after wake rather than execute every missed event.

The helper may need its own Full Disk Access. In Finder, right-click Mars.app → Show Package Contents → Contents → MacOS, then drag `mars-scan` into the Full Disk Access list if macOS permits. Check the first real scheduled report for permission errors; approving the GUI is not proof the helper can access the same folders.

If you move or replace Mars.app, open it and Save schedule again to refresh the helper path and job. Concurrent engine operations do not overlap: a scheduled job encountering a busy engine exits and does not retry that occurrence. History refreshes every ten seconds while the GUI is open.

## Reports and detections

Detections are not automatically malware confirmations. Heuristics, engine-limit alerts, and false positives require review. Do not open flagged files; use Reveal in Finder to locate them and independently investigate before deciding what to do.

Mars never deletes, moves, or quarantines files. Open raw log shows ClamAV output. Export report creates a JSON file containing local paths and detection names; review it before sharing.

Update failures can stop a scan before a raw scan log exists. In that case, check `Logs/definitions.log` in Open local data. Scan reports and their referenced logs are retained for the latest 200 scans; raw logs are capped at approximately 32 MiB. `schedule.log` and `schedule-error.log` are launchd diagnostic files and are not rotated automatically.

## Update or uninstall

App updates are manual through [GitHub Releases](https://github.com/paulfxyz/mars/releases). Quit the GUI, allow any scheduled scan to finish, replace the app, then reopen it and Save schedule again. Updating definitions is separate from upgrading the engine; use `brew upgrade clamav` in Terminal for an engine upgrade.

To uninstall, first disable scheduled scans and Save schedule in Mars. Then quit and delete Mars.app. Your data is retained until you choose to delete `~/Library/Application Support/mars/`. Homebrew's ClamAV installation is independent; remove it yourself with `brew uninstall clamav` only if nothing else uses it.

If the app is already gone, unload its job with:

```sh
launchctl bootout "gui/$(id -u)/com.paulfleury.mars.scan"
```

Then remove only `~/Library/LaunchAgents/com.paulfleury.mars.scan.plist`. Do not remove unrelated LaunchAgents.
