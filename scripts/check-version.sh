#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(sed -n 's/^VERSION=//p' scripts/package.sh)
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
require() {
  if ! grep -Fq "$2" "$1"; then
    printf 'Version consistency error in %s: expected %s\n' "$1" "$2" >&2
    exit 1
  fi
}
require README.md "https://img.shields.io/badge/release-v$VERSION-bf3829?style=flat-square"
require README.md "https://github.com/paulfxyz/mars/releases/tag/v$VERSION"
require README.md "Mars-$VERSION-macOS-universal.zip"
require Sources/MarsCore/AppUpdater.swift "public static let fallback = \"$VERSION\""
require "docs/RELEASE-$VERSION.md" "# Mars $VERSION"
printf 'Release version references agree: %s\n' "$VERSION"
