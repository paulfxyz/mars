# Mars identity

The app and public-facing brand are **Mars**. The GitHub repository, executable, and local data directory use lowercase `mars`.

## Character

Mars is an original Roman-inspired adult guardian in a manga/editorial illustration style. His clam-shell shield channels the separately installed ClamAV engine, while a luminous protective dome defends a laptop from abstract digital-virus creatures. This is a metaphor, not a claim of real-time or comprehensive protection.

The character is not a video-game character, and the shell is not an official ClamAV logo or mascot. The illustration is AI-generated original project artwork. The app icon is drawn separately in `scripts/build-icon.swift` for legibility at small sizes.

## Palette and type

- Vermilion: `#C23829`, primary actions and warm character accent.
- Charcoal: `#1F2424`, navigation and visual grounding.
- Ivory: `#F7F5F0`, warm light surfaces.
- Muted teal: `#26735C`, readiness and successful inspected-scope results.
- Native system sans-serif: controls, metadata, readable operational information.
- Native system serif: editorial headings and the Mars wordmark.

Colors are direction values; the native implementation uses adaptive system surfaces for dark mode. Never rely only on color to convey outcome.

## Usage

Use the guardian illustration for the README hero and the app overview, preserving its uncluttered left side and the visible shield/laptop relationship. Use the shield app icon for app bundles and small placements; do not squeeze the entire character into a menu-bar glyph.

Keep security claims precise: “Your Mac. Defended with ClamAV.” describes the intended utility, while setup and reports must always distinguish not installed, ready to scan, scanning, cancelled, incomplete, and no detections among inspected files. Never label an unscanned Mac “safe.”
