#!/usr/bin/env bash
# Single verification entry point for humans, agents and CI.
#   scripts/check.sh            Debug build + full XCTest suite + iOS remote (Simulator build)
#   scripts/check.sh --release  additionally Release builds with strict signature check
#   scripts/check.sh --build    Debug builds only (fast compile check)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

# xcode-select may point at the Command Line Tools. Pick a full Xcode without
# changing system state; an explicit DEVELOPER_DIR always wins.
if [[ -z "${DEVELOPER_DIR:-}" ]] && ! xcodebuild -version >/dev/null 2>&1; then
    xcode="$(ls -d /Applications/Xcode*.app 2>/dev/null | grep -v Xcodes.app | sort -V | tail -1 || true)"
    [[ -n "$xcode" ]] || { echo "error: no Xcode installation found" >&2; exit 1; }
    export DEVELOPER_DIR="$xcode/Contents/Developer"
fi
xcodebuild -version | sed -n 1p

mode="${1:-test}"
common=(-project MacPrompter.xcodeproj -scheme macprompter -destination 'platform=macOS,arch=arm64' -derivedDataPath build)
# The iOS remote shares the protocol code; its logic is tested in the macOS suite.
remote=(-project MacPrompter.xcodeproj -scheme "macprompter Remote" -derivedDataPath build)
log="build/check.log"
mkdir -p build

run() {
    if ! xcodebuild "$@" >"$log" 2>&1; then
        grep -E "error:|Failing tests:|failed|\*\* .* FAILED" "$log" | head -60 >&2 || true
        echo "xcodebuild failed; full log: $log" >&2
        exit 1
    fi
    grep -E "warning: " "$log" | grep -vE "appintentsmetadataprocessor|Could not read priors" | sort -u | head -30 || true
}

build_remote() {
    log="build/check-remote.log"
    run build "${remote[@]}" -configuration Debug -destination 'generic/platform=iOS Simulator'
    echo "REMOTE BUILD OK"
}

case "$mode" in
    --build)
        scripts/make_fixtures.sh
        run build "${common[@]}" -configuration Debug
        echo "BUILD OK"
        build_remote
        ;;
    test|--test|--release)
        scripts/make_fixtures.sh
        run test "${common[@]}"
        grep -E "Executed [0-9]+ tests" "$log" | tail -1
        echo "TESTS OK"
        build_remote
        if [[ "$mode" == "--release" ]]; then
            log="build/check.log"
            run build "${common[@]}" -configuration Release
            codesign --verify --strict --verbose=2 build/Build/Products/Release/macprompter.app
            log="build/check-remote.log"
            # Device build without a team: proves it compiles for iphoneos; signing needs Signing.local.xcconfig.
            run build "${remote[@]}" -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
            echo "RELEASE OK"
        fi
        ;;
    *)
        echo "usage: scripts/check.sh [--build|--release]" >&2
        exit 2
        ;;
esac
