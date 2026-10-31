# Security

Mars is a community preview, not an audited endpoint-protection system. Its security boundary is a native GUI and per-user background helper around separately installed ClamAV binaries.

## Design choices

- Process arguments are passed directly to `Process`, not composed into shell commands. Paths remain individual arguments after `--`.
- The only shell-install command is the static official Homebrew bootstrap, shown through an explicit user-confirmed Terminal operation. No selected path is interpolated into that command.
- No deletion, move, copy-to-quarantine, sample submission, root scanner, privileged helper, `clamd` service, network listener, or kernel extension is installed by Mars.
- Updates, installation, and scans share an advisory `flock` across GUI and helper. Kernel release of the lock prevents stale process locks after crashes.
- The engine keeps its default archive and file-size limits; exceeded-limit alerts are enabled. No result is a guarantee of exhaustive inspection.
- The official engine is installed independently, so its licensing, updates, authenticity, and vulnerability management remain relevant.

## Important limits

The application is not sandboxed: it needs user-authorized filesystem scanning and Homebrew subprocesses. The ad-hoc signature is not notarization or Developer ID verification. Homebrew and the local user can change engine binaries; Mars does not independently pin their hashes. Users with access to the local account can read or alter its reports and definitions.

Malicious files can target vulnerabilities in any parser, including antivirus engines. Keep the ClamAV engine and macOS current. Do not open flagged files, and do not assume an empty detection list proves safety.

## Reporting

Do not publish private filenames, scan contents, or exploit instructions in a public issue. Use [GitHub's private vulnerability reporting](https://github.com/paulfxyz/mars/security/advisories/new) if enabled; otherwise contact the maintainer through the contact route on [paulfleury.com](https://paulfleury.com). Please provide a minimal harmless reproduction and the macOS, Mars, and ClamAV versions.
