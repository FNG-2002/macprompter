@AGENTS.md

## Claude-spezifisch

- Projekt-Skills unter `.claude/skills/` (Symlinks auf `.agents/skills/`): `macos-build`, `macos-patterns`, `macos-notch-ui`, `macos-settings-ui`, `macos-release`. Vor nativen macOS-APIs (Fenster-Level, Panels, Aktivierung, Hotkeys) `macos-patterns` heranziehen. Für Releases gilt `docs/RELEASING.md`, nicht der Sparkle-Teil von `macos-release`.
- Für den autonomen Ablauf benötigt der Agent Freigaben für `scripts/check.sh`, `xcodebuild`, `python3 scripts/generate_project.py`, `git` (ohne Force-Push) und `gh pr`/`gh run`. Diese richtet der Maintainer über den Auto-Mode bzw. `.claude/settings.json` ein; persönliche Ergänzungen gehören in `.claude/settings.local.json` (nicht eingecheckt).
- Für Verifikation immer `scripts/check.sh` statt eigener `xcodebuild`-Varianten verwenden; lange Läufe im Hintergrund starten.
