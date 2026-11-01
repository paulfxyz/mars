# Security

Mars is not an externally audited endpoint-protection system. Its security boundary is a native GUI and per-user background helper around separately installed ClamAV and optional YARA-X binaries; version 1.0.0 does not imply security certification.

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

## Additional source boundaries in 1.0.0

Unofficial sources are off by default and require explicit terms consent. Source updates and rollback use the same cross-process operation lock as scans. Downloaded updates are staged and checked by the target engine before activation; one previous copy is retained. A rejected update does not silently replace the active pack.

Elastic's four selected rule files and license are pinned to an immutable commit and expected SHA-256 hashes. A reviewed Mars change is required to advance that pin; this is not a promise to track all upstream threat intelligence automatically. Local YARA imports reject any occurrence of the include keyword, including comments/strings, to conservatively prevent compiler-time reads of unrelated files. This can reject some otherwise valid rules.

Sanesecurity downloads use its public rsync mirror. Content authenticity is checked against the embedded vendor key in an isolated public-key ring without starting a GPG agent. This is a legacy DSA vendor key, not a newly issued modern Mars key; pinning does not upgrade its cryptographic strength. Signed payload dates are exposed because download time is not evidence of current threat coverage.

SecuriteInfo endpoints are restricted to official HTTPS signature paths. Private URLs are access-restricted local configuration, not encrypted Keychain entries. They are kept out of report metadata, exports, displayed transport logs, and process arguments, but another process with the same user privileges can read local files. Engine validation checks format, not the subscription's legal scope or signature efficacy.

YARA-X has explicit file-size, enumeration, symlink, archive, and per-source runtime limits. Missing requested rules, engine errors, and candidate-list access issues must not become a clean scan result. No result is proof that the Mac is safe; a pattern match is evidence to review, not necessarily a confirmed infection.

## Reporting a vulnerability

Do not publish private filenames, scan contents, or exploit instructions in a public issue. Use [GitHub's private vulnerability reporting](https://github.com/paulfxyz/mars/security/advisories/new) if enabled; otherwise contact the maintainer through the contact route on [paulfleury.com](https://paulfleury.com). Please provide a minimal harmless reproduction and the macOS, Mars, and ClamAV versions.
