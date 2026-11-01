#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=1.1.0
APP="$PWD/dist/Mars.app"
mkdir -p dist
for ARCH in arm64 x86_64; do
  swift build -c release --arch "$ARCH"
done
rm -rf "$APP"
mkdir -p "$APP/Contents/"{MacOS,Resources}
for BINARY in mars mars-scan; do
  lipo -create ".build/arm64-apple-macosx/release/$BINARY" ".build/x86_64-apple-macosx/release/$BINARY" -output "$APP/Contents/MacOS/$BINARY"
done
cp assets/mars-guardian.png "$APP/Contents/Resources/"
swift scripts/build-icon.swift assets/app.png
ICONSET=dist/AppIcon.iconset
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" assets/app.png --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "$DOUBLE" "$DOUBLE" assets/app.png --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Clear dict" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.paulfleury.mars" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string Mars" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Mars" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string mars" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 110" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 13.0" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSAppleEventsUsageDescription string Mars opens a visible Terminal window only when you confirm installation of Homebrew." "$APP/Contents/Info.plist"
codesign --force --sign - "$APP/Contents/MacOS/mars-scan"
codesign --force --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
lipo "$APP/Contents/MacOS/mars" -verify_arch arm64 x86_64
lipo "$APP/Contents/MacOS/mars-scan" -verify_arch arm64 x86_64
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/Mars-${VERSION}-macOS-universal.zip"
(cd dist && shasum -a 256 "Mars-${VERSION}-macOS-universal.zip" > SHA256SUMS.txt)
echo "Packaged Mars $VERSION (Apple silicon + Intel, macOS 13+). Ad-hoc signed, not notarized."
