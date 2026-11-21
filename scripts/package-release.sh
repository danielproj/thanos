#!/bin/bash
# Produces a signed, notarized, stapled release of Thanos.
#
# Usage: scripts/package-release.sh --version X.Y.Z --build N [--out DIR]
# Env:
#   THANOS_DEVELOPER_ID     codesigning identity (default: the first "Developer ID Application" identity in the keychain)
#   THANOS_NOTARY_PROFILE   notarytool keychain profile (xcrun notarytool store-credentials)
#
#   THANOS_SPARKLE_ACCOUNT  keychain account of the Sparkle EdDSA update key (default: thanos)
#
# Output in DIR (default artifacts/release): Thanos-X.Y.Z.dmg, .dmg.sha256, appcast.xml, sbom.cdx.json, release-notes.md
# appcast.xml is the auto-update feed: attach it to the GitHub release, which the app reads at
# https://github.com/danielproj/thanos/releases/latest/download/appcast.xml
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
THANOS_CHANNEL=release THANOS_VERSION="$version" THANOS_BUILD="$build" scripts/build-app.sh

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
app="$work/Thanos.app"
cp -R build/Thanos.app "$app"
# Sign Sparkle's nested code inside-out (Sparkle's documented order), then the app.
fw="$app/Contents/Frameworks/Sparkle.framework"
sign() { codesign --force --options runtime --timestamp --sign "$identity" "$@"; }
for xpc in "$fw/Versions/B/XPCServices/Installer.xpc"; do [ -e "$xpc" ] && sign "$xpc"; done
[ -e "$fw/Versions/B/XPCServices/Downloader.xpc" ] && sign --preserve-metadata=entitlements "$fw/Versions/B/XPCServices/Downloader.xpc"
sign "$fw/Versions/B/Autoupdate"
sign "$fw/Versions/B/Updater.app"
sign "$fw"
sign "$app"
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

# Auto-update feed, signed with the Sparkle EdDSA key in the keychain.
sign_update=".build/artifacts/sparkle/Sparkle/bin/sign_update"
attrs="$("$sign_update" --account "${THANOS_SPARKLE_ACCOUNT:-thanos}" "$dmg")" || die "the update could not be signed (is the Sparkle key in the keychain?)" 65
[[ "$attrs" == *'sparkle:edSignature="'* ]] || die "sign_update produced no signature" 65
minimum="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist")"
repo_url="https://github.com/danielproj/thanos"
cat > "$out/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Thanos</title>
    <link>$repo_url</link>
    <language>en</language>
    <item>
      <title>Thanos $version</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$repo_url/releases</sparkle:fullReleaseNotesLink>
      <description><![CDATA[<p>Thanos $version is available. See <a href="$repo_url/releases/tag/v$version">what's new</a>.</p>]]></description>
      <enclosure url="$repo_url/releases/download/v$version/Thanos-$version.dmg" type="application/octet-stream" $attrs/>
    </item>
  </channel>
</rss>
XML
xmllint --noout "$out/appcast.xml" || die "appcast.xml is not valid XML" 65
commit="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
python3 - "$out/sbom.cdx.json" "$version" "$commit" <<'PY'
import json, sys, uuid, datetime
out, version, commit = sys.argv[1:4]
json.dump({
  "bomFormat": "CycloneDX", "specVersion": "1.5", "serialNumber": f"urn:uuid:{uuid.uuid4()}", "version": 1,
  "metadata": {"timestamp": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
               "component": {"type": "application", "name": "Thanos", "version": version,
                             "properties": [{"name": "git.commit", "value": commit}]}},
  "components": [{"type": "framework", "bom-ref": "sparkle", "name": "Sparkle", "version": "2.10.1",
                  "licenses": [{"license": {"id": "MIT"}}], "purl": "pkg:github/sparkle-project/Sparkle@2.10.1"}],
  "dependencies": [{"ref": "Thanos", "dependsOn": ["sparkle"]}],
}, open(out, "w"), indent=2)
PY
cat > "$out/release-notes.md" <<NOTES
Install \`Thanos-$version.dmg\` and drag Thanos into Applications. For macOS 26 or later on Apple Silicon. The app and disk image are Developer ID signed, notarized and stapled.

Installed copies of Thanos 0.3.0 or later update themselves from \`appcast.xml\`. The SHA-256 of the disk image is in \`Thanos-$version.dmg.sha256\`. \`sbom.cdx.json\` is the software bill of materials. Version $version, build $build.
NOTES
echo "Release artifacts in $out"
