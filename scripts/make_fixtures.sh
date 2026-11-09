#!/usr/bin/env bash
# Creates the synthetic speech fixtures for SpeechIntegrationTests with the
# local macOS voices. The audio is generated on each machine instead of being
# committed: Apple's license for the system voices does not allow publishing
# their output (docs/DECISIONS.md, ADR-24).
#   scripts/make_fixtures.sh          create missing files
#   scripts/make_fixtures.sh --force  recreate all files
set -euo pipefail

dir="$(cd "$(dirname "$0")/.." && pwd)/MacPrompterTests/Fixtures"
mkdir -p "$dir"

make() {
    local name="$1" voice="$2" text="$3" out="$dir/$1.aiff"
    [[ "${FORCE:-}" == 1 || ! -s "$out" ]] || return 0
    # Without the preferred voice (e.g. on CI) the default voice still yields a
    # valid file; the speech tests skip there anyway because the models are missing.
    say -v "$voice" -o "$out" "$text" 2>/dev/null || say -o "$out" "$text"
}

[[ "${1:-}" == "--force" ]] && FORCE=1
make de Anna "Willkommen bei macprompter. Gute Geschichten beginnen mit einem Gedanken, den wir teilen möchten."
make en Samantha "Hello and welcome. Today I want to share a simple idea. The best way to connect with people is to be yourself."
make de-aside Anna "Heute untersuchen wir. Das erinnert mich übrigens an eine Geschichte aus meinem letzten Urlaub. Solarmodule und moderne Speicher liefern nachhaltige Energie."
make en-aside Samantha "Welcome, everyone. Let me tell you a quick story about my recent vacation. The batteries store clean energy for tomorrow."
