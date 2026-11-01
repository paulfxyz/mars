# Mars native interface

These screenshots were captured from the running SwiftUI/AppKit app, not generated interface mockups. Every capture uses `--demo` mode with clearly labeled synthetic data; a displayed scan result is illustrative, not evidence of a scan of a real Mac.

## Overview

The original guardian illustration anchors the warm ivory dashboard. Engine readiness, definition freshness, and the saved schedule remain separate from scan results.

<img src="screenshot-overview.png" width="100%" alt="Mars native overview in light appearance">

## Manual scan

Choose the startup disk, home, or selected folders. Pre-scan definition updates are enabled by default, and scanning never removes files.

<img src="screenshot-scan.png" width="100%" alt="Mars native manual scan controls">

## Detection sources

ClamAV remains the baseline, with optional YARA-X inclusion and source-by-source consent, validation, freshness, license, and rollback controls. The source list is a normal scrollable native screen.

<img src="screenshot-sources.png" width="100%" alt="Mars native two-engine and detection source controls">

## During a scan

Plain-language stages, honest counters, elapsed time, safe stopping, and an expandable read-only terminal stay together. Synthetic progress does not imply that a real machine was scanned.

<img src="screenshot-scanning.png" width="100%" alt="Mars native scan progress with understandable explanations and engine console">

## Understanding the result

The report explains what a match means, identifies its engine/source, lists coverage gaps and suggested next steps, and offers safe actions. The example is a deliberately synthetic rule match, not a malware sample.

<img src="screenshot-results.png" width="100%" alt="Mars native results sheet with interpretation, source attribution, and safe actions">

## Scheduled routines

Daily and weekly choices are saved explicitly to a per-user macOS LaunchAgent. This is a normal scrollable window; further controls are below the captured viewport.

<img src="screenshot-schedule.png" width="100%" alt="Mars native schedule settings and scan scope">

## Local history

Reports separate completed, detected, incomplete, failed, and cancelled outcomes. This capture contains one synthetic completed report.

<img src="screenshot-history.png" width="100%" alt="Mars native local scan history with a synthetic report">

## Engine and permissions

Engine setup, definition updates, Full Disk Access guidance, local data, and source access share a straightforward settings screen. The last footer continues below the captured viewport.

<img src="screenshot-settings.png" width="100%" alt="Mars native engine, privacy permissions, and local data settings">

## Dark appearance

The interface adapts its native surfaces while retaining the warm guardian artwork. Outcome labels accompany color so results do not depend on color alone.

<img src="screenshot-overview-dark.png" width="100%" alt="Mars native overview in dark appearance">

## Minimum window

At the minimum 1020×740 content size, navigation and primary actions remain available. Content scrolls vertically rather than squeezing into overlapping columns.

<img src="screenshot-overview-compact.png" width="100%" alt="Mars native overview at minimum window size">

## App icon

The shield and original clam-fan motif echo the guardian's artwork in a legible small-format mark. Both [PNG](../assets/app.png) and [ICNS](../assets/app.icns) formats are committed.

<img src="../assets/app.png" width="192" height="192" alt="Mars vermilion app icon with an ivory shield and teal clam fan">
