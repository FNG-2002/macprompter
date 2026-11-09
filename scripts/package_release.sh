#!/usr/bin/env bash
# Builds the distributable macprompter-<version>.dmg (used by .github/workflows/release.yml,
# also runnable locally). Signing, strongest available first:
#   1. Developer ID (MACOS_DEVELOPER_ID set): hardened runtime, timestamp, notarization
#      when NOTARY_APPLE_ID, NOTARY_TEAM_ID and NOTARY_PASSWORD are set.
#   2. MACOS_SIGN_IDENTITY: any code-signing identity in the keychain, e.g. the project's
#      self-signed release certificate on CI. Stable across releases, so macOS keeps
#      microphone and input monitoring grants after updates. Not notarized.
#   3. Ad hoc: works, but grants have to be renewed after every update.
# Output: build/release/macprompter-<version>.dmg and .sha256, plus build/release/signing.txt.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [[ -z "${DEVELOPER_DIR:-}" ]] && ! xcodebuild -version >/dev/null 2>&1; then
    xcode="$(ls -d /Applications/Xcode*.app 2>/dev/null | grep -v Xcodes.app | sort -V | tail -1 || true)"
    export DEVELOPER_DIR="$xcode/Contents/Developer"
fi

version="$(python3 scripts/release_notes.py --version)"
out="build/release"
rm -rf "$out"
mkdir -p "$out"

# Universal Release build; ONLY_ACTIVE_ARCH is NO for Release.
xcodebuild build -project MacPrompter.xcodeproj -scheme macprompter -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath build >"$out/build.log" 2>&1 \
    || { grep -E "error:" "$out/build.log" | head -30 >&2; exit 1; }

staging="$out/dmg"
mkdir -p "$staging"
ditto build/Build/Products/Release/macprompter.app "$staging/macprompter.app"
app="$staging/macprompter.app"
built_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
[[ "$built_version" == "$version" ]] || { echo "error: built $built_version, expected $version" >&2; exit 1; }

identity="-"; mode="adhoc"; timestamp="--timestamp=none"
if [[ -n "${MACOS_DEVELOPER_ID:-}" ]]; then
    identity="$MACOS_DEVELOPER_ID"; mode="developer-id"; timestamp="--timestamp"
elif [[ -n "${MACOS_SIGN_IDENTITY:-}" ]]; then
    identity="$MACOS_SIGN_IDENTITY"; mode="self-signed"
fi

# Keep the entitlements Xcode signed with; nested helpers first, then the app that seals them.
entitlements="$out/entitlements"
mkdir -p "$entitlements"
for helper in "$app/Contents/Helpers/"*; do
    codesign -d --entitlements - --xml "$helper" >"$entitlements/$(basename "$helper").plist"
    codesign --force --options runtime $timestamp --preserve-metadata=identifier \
        --entitlements "$entitlements/$(basename "$helper").plist" --sign "$identity" "$helper"
done
codesign -d --entitlements - --xml "$app" >"$entitlements/app.plist"
if grep -rq "get-task-allow" "$entitlements"; then echo "error: release build carries get-task-allow" >&2; exit 1; fi
codesign --force --options runtime $timestamp --entitlements "$entitlements/app.plist" --sign "$identity" "$app"
codesign --verify --strict --deep --verbose=2 "$app"
codesign -dvv "$app" 2>&1 | grep -E "^(Authority|Signature|TeamIdentifier)=" || true
echo "$mode" >"$out/signing.txt"

ln -s /Applications "$staging/Applications"
dmg="$out/macprompter-$version.dmg"
hdiutil create -volname "macprompter $version" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg" >/dev/null
[[ "$identity" == "-" ]] || codesign --force $timestamp --sign "$identity" "$dmg"

if [[ "$mode" == "developer-id" && -n "${NOTARY_APPLE_ID:-}" ]]; then
    xcrun notarytool submit "$dmg" --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" \
        --password "$NOTARY_PASSWORD" --wait
    xcrun stapler staple "$dmg"
    echo "notarized" >"$out/signing.txt"
fi

(cd "$out" && shasum -a 256 "$(basename "$dmg")" >"$(basename "$dmg").sha256")
rm -rf "$staging" "$entitlements"
echo "PACKAGED $dmg ($(cat "$out/signing.txt"))"
