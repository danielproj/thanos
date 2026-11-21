#!/bin/bash
# Builds build/Thanos.app for local use (ad-hoc signed).
# Usage: scripts/build-app.sh [--open]        Env: THANOS_VERSION (default 0.0.0-dev), THANOS_BUILD (default 0)
set -euo pipefail
cd "$(dirname "$0")/.."
version="${THANOS_VERSION:-0.0.0-dev}"
build="${THANOS_BUILD:-0}"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Thanos"
APP=build/Thanos.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Thanos"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" -c "Set :CFBundleVersion $build" "$APP/Contents/Info.plist"
if [ ! -f Resources/AppIcon.icns ]; then
  rm -rf build/AppIcon.iconset
  swift scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Ad-hoc, but with a designated requirement tied to the bundle id rather than the binary hash,
# so a Full Disk Access grant survives rebuilds.
codesign --force --sign - -r='designated => identifier "com.danyilproskurka.thanos"' "$APP"
echo "Built $APP ($version, build $build)"
if [ "${1:-}" = "--open" ]; then open "$APP"; fi
