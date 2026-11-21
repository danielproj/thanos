#!/bin/bash
# Everything CI checks, runnable locally. Uses no secrets.
set -euo pipefail
cd "$(dirname "$0")/.."
swift --version
swift build -c release --arch arm64
swift test
scripts/build-app.sh
codesign --verify --strict build/Thanos.app
plutil -lint Resources/Info.plist
# The app must never ship attribution to tools in its metadata or docs.
if grep -RIniE "co-authored-by|generated with" --exclude-dir=.build --exclude-dir=build --exclude-dir=.git --exclude=ci.sh . ; then
  echo "error: attribution text found" >&2; exit 1
fi
echo "ci: ok"
