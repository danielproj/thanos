#!/bin/bash
# Produces a signed, notarized, stapled release of Thanos.
#
# Usage: scripts/package-release.sh --version X.Y.Z --build N [--out DIR]
# Env:
#   THANOS_DEVELOPER_ID     codesigning identity (default: the first "Developer ID Application" identity in the keychain)
#   THANOS_NOTARY_PROFILE   notarytool keychain profile (xcrun notarytool store-credentials)
#
# Output in DIR (default artifacts/release): Thanos-X.Y.Z.dmg, .dmg.sha256, sbom.cdx.json, release-notes.md
set -euo pipefail
cd "$(dirname "$0")/.."
die() { echo "error: $1" >&2; exit "${2:-1}"; }

version=""; build=""; out="artifacts/release"
while [ $# -gt 0 ]; do
  case "$1" in
    --version) version="$2"; shift 2 ;;
    --build) build="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    *) die "unknown argument $1" 64 ;;
  esac
done
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "--version must be X.Y.Z" 64
[[ "$build" =~ ^[0-9]+$ ]] || die "--build must be a number" 64

identity="${THANOS_DEVELOPER_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
profile="${THANOS_NOTARY_PROFILE:-}"
[ -n "$identity" ] || die "no Developer ID Application identity found" 65
[ -n "$profile" ] || die "THANOS_NOTARY_PROFILE must name a notarytool keychain profile" 66

scripts/ci.sh
THANOS_VERSION="$version" THANOS_BUILD="$build" scripts/build-app.sh

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
app="$work/Thanos.app"
cp -R build/Thanos.app "$app"
codesign --force --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --deep --strict "$app"
[[ "$(codesign -dvv "$app" 2>&1 | grep -m1 '^Authority=')" == "Authority=Developer ID Application: "* ]] || die "not signed by a Developer ID Application identity" 65

ditto -c -k --keepParent "$app" "$work/Thanos-app.zip"
xcrun notarytool submit "$work/Thanos-app.zip" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"

mkdir -p "$out"; rm -f "$out"/Thanos-*.dmg*
stage="$work/dmg"; mkdir -p "$stage"
cp -R "$app" "$stage/"; ln -s /Applications "$stage/Applications"
dmg="$out/Thanos-$version.dmg"
hdiutil create -quiet -volname Thanos -srcfolder "$stage" -format UDZO -fs APFS "$dmg"
codesign --force --timestamp --sign "$identity" "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
xcrun stapler staple "$dmg"
spctl -a -t open --context context:primary-signature -v "$dmg"

( cd "$out" && shasum -a 256 "Thanos-$version.dmg" > "Thanos-$version.dmg.sha256" )
commit="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
python3 - "$out/sbom.cdx.json" "$version" "$commit" <<'PY'
import json, sys, uuid, datetime
out, version, commit = sys.argv[1:4]
json.dump({
  "bomFormat": "CycloneDX", "specVersion": "1.5", "serialNumber": f"urn:uuid:{uuid.uuid4()}", "version": 1,
  "metadata": {"timestamp": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
               "component": {"type": "application", "name": "Thanos", "version": version,
                             "properties": [{"name": "git.commit", "value": commit}]}},
  "components": [],
  "dependencies": [{"ref": "Thanos", "dependsOn": []}],
}, open(out, "w"), indent=2)
PY
cat > "$out/release-notes.md" <<NOTES
Install \`Thanos-$version.dmg\` and drag Thanos into Applications. For macOS 26 or later on Apple Silicon. The app and disk image are Developer ID signed, notarized and stapled.

The SHA-256 of the disk image is in \`Thanos-$version.dmg.sha256\`. \`sbom.cdx.json\` is the software bill of materials (Thanos has no third-party dependencies). Version $version, build $build.
NOTES
echo "Release artifacts in $out"
