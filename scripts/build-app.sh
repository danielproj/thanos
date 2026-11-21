#!/bin/bash
# Builds build/Thanos.app (ad-hoc signed).
# Usage: scripts/build-app.sh [--open]
# Env: THANOS_VERSION (default 0.0.0-dev), THANOS_BUILD (default 0),
#      THANOS_CHANNEL  dev (default) or release.
#
# A dev build is "Thanos Dev" with bundle id com.danyilproskurka.thanos.dev and no update feed. It must never share
# the release identifier: macOS keys privacy grants such as Full Disk Access to the bundle id, and an ad-hoc build
# carrying the release id fails the release's code requirement, which has cost the installed app its grant.
set -euo pipefail
cd "$(dirname "$0")/.."
version="${THANOS_VERSION:-0.0.0-dev}"
build="${THANOS_BUILD:-0}"
channel="${THANOS_CHANNEL:-dev}"
case "$channel" in
  release) bundle_id="com.danyilproskurka.thanos" ;;
  dev) bundle_id="com.danyilproskurka.thanos.dev" ;;
  *) echo "error: THANOS_CHANNEL must be dev or release" >&2; exit 64 ;;
esac

swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
BIN="$BIN_DIR/Thanos"
APP=build/Thanos.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/Thanos"
# Sparkle (auto-update). ditto keeps the framework's symlinks intact.
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plist="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" -c "Set :CFBundleVersion $build" -c "Set :CFBundleIdentifier $bundle_id" "$plist"
if [ "$channel" = dev ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Thanos Dev" -c "Delete :SUFeedURL" "$plist"
fi
if [ ! -f Resources/AppIcon.icns ]; then
  rm -rf build/AppIcon.iconset
  swift scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Ad-hoc, but with a designated requirement tied to the bundle id rather than the binary hash,
# so a Full Disk Access grant survives rebuilds.
codesign --force --sign - "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - -r="designated => identifier \"$bundle_id\"" "$APP"
echo "Built $APP ($bundle_id $version, build $build)"
if [ "${1:-}" = "--open" ]; then open "$APP"; fi
