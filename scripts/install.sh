#!/usr/bin/env bash
# Local install of the verified Release build into /Applications.
# Signs with an "Apple Development" identity when one is available: macOS then
# ties privacy grants (Input Monitoring, microphone) to the certificate instead
# of the exact build, so they survive updates. Without one it stays ad hoc.
#   scripts/install.sh                          check.sh --release, then install
#   scripts/install.sh --quick                  Release build only, for a quick test version
#   MACPROMPTER_SIGN_IDENTITY=- scripts/install.sh   force ad hoc
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [[ "${1:-}" == "--quick" ]]; then
    if [[ -z "${DEVELOPER_DIR:-}" ]] && ! xcodebuild -version >/dev/null 2>&1; then
        xcode="$(ls -d /Applications/Xcode*.app 2>/dev/null | grep -v Xcodes.app | sort -V | tail -1 || true)"
        export DEVELOPER_DIR="$xcode/Contents/Developer"
    fi
    xcodebuild build -project MacPrompter.xcodeproj -scheme macprompter -configuration Release \
        -destination 'platform=macOS,arch=arm64' -derivedDataPath build >build/install.log 2>&1 \
        || { grep -E "error:" build/install.log | head -20 >&2; exit 1; }
    echo "RELEASE BUILD OK (untested)"
else
    scripts/check.sh --release
fi
built="build/Build/Products/Release/macprompter.app"
target="/Applications/macprompter.app"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
ditto "$built" "$staging/macprompter.app"

identity="${MACPROMPTER_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')}"
if [[ -n "$identity" && "$identity" != "-" ]]; then
    # Nested helpers first (own sandbox and entitlements), then the app that seals them.
    for helper in "$staging/macprompter.app/Contents/Helpers/"*; do
        codesign -d --entitlements - --xml "$helper" >"$staging/helper.plist" 2>/dev/null
        codesign --force --options runtime --timestamp=none --preserve-metadata=identifier \
            --entitlements "$staging/helper.plist" --sign "$identity" "$helper"
    done
    codesign -d --entitlements - --xml "$built" >"$staging/entitlements.plist" 2>/dev/null
    codesign --force --options runtime --timestamp=none --entitlements "$staging/entitlements.plist" \
        --sign "$identity" "$staging/macprompter.app"
    echo "SIGNED: $identity"
else
    echo "SIGNED: ad hoc (privacy grants must be renewed after each install)"
fi
codesign --verify --strict "$staging/macprompter.app"

# Quit only a running copy; "tell application" would otherwise launch it.
if pgrep -f "$target/Contents/MacOS/macprompter" >/dev/null; then
    osascript -e 'tell application id "io.github.fng-2002.macprompter" to quit'
    for _ in $(seq 1 40); do
        pgrep -f "$target/Contents/MacOS/macprompter" >/dev/null || break
        sleep 0.25
    done
fi
rm -rf "$target"
ditto "$staging/macprompter.app" "$target"
open "$target"
echo "INSTALLED $target"
