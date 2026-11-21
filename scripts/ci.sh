#!/bin/bash
# Everything CI checks, runnable locally. Uses no secrets.
set -euo pipefail
cd "$(dirname "$0")/.."
swift --version
swift build -c release --arch arm64
swift test
scripts/build-app.sh
# Dev builds must never carry the release identifier or the update feed.
[ "$(plutil -extract CFBundleIdentifier raw build/Thanos.app/Contents/Info.plist)" = com.danyilproskurka.thanos.dev ]
! plutil -extract SUFeedURL raw build/Thanos.app/Contents/Info.plist >/dev/null 2>&1
codesign --verify --strict --deep build/Thanos.app
# Auto-update must be wired: Sparkle embedded and loadable, feed and public key present.
test -d build/Thanos.app/Contents/Frameworks/Sparkle.framework
otool -L build/Thanos.app/Contents/MacOS/Thanos | grep -q "@rpath/Sparkle.framework"
otool -l build/Thanos.app/Contents/MacOS/Thanos | grep -q "@executable_path/../Frameworks"
for key in SUFeedURL SUPublicEDKey; do /usr/libexec/PlistBuddy -c "Print :$key" Resources/Info.plist >/dev/null; done
plutil -lint Resources/Info.plist
# The app must never ship attribution to tools in its metadata or docs.
if grep -RIniE "co-authored-by|generated with" --exclude-dir=.build --exclude-dir=build --exclude-dir=.git --exclude=ci.sh . ; then
  echo "error: attribution text found" >&2; exit 1
fi
echo "ci: ok"
