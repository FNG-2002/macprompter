# Mitmachen

Danke, dass du macprompter verbessern willst! Fehlerberichte, Ideen und Pull Requests sind willkommen.

## Wie Entscheidungen fallen

macprompter ist Open Source, aber kein Gemeinschaftsprojekt mit mehreren Maintainern. **Über Richtung, Funktionen und jeden Merge entscheidet der Maintainer** ([@FNG-2002](https://github.com/FNG-2002)). Nur er hat Schreibrechte; `main` ist geschützt und ändert sich nur über Pull Requests mit grüner CI. Ein Pull Request kann deshalb auch abgelehnt werden, wenn er technisch gut ist, aber nicht zu den Produktprinzipien passt.

## Fehler melden und Ideen vorschlagen

- **Fehler:** [Issue „Fehler melden“](https://github.com/FNG-2002/macprompter/issues/new?template=bug_report.yml) mit macOS-Version, macprompter-Version (Hilfe → Lizenzen und Danksagungen bzw. Einstellungen → Über macprompter) und Schritten zum Nachstellen. Bitte keine privaten Skripttexte anhängen.
- **Ideen:** [Issue „Idee vorschlagen“](https://github.com/FNG-2002/macprompter/issues/new?template=feature_request.yml). Bei größeren Vorhaben bitte zuerst ein Issue, bevor du Zeit in Code steckst.
- **Sicherheitslücken** nie öffentlich, sondern wie in [SECURITY.md](SECURITY.md) beschrieben.

## Pull Requests

1. Repository forken, Branch anlegen (`fix/…`, `feat/…`, `docs/…`).
2. Lies [AGENTS.md](AGENTS.md): Die Regeln dort gelten für Menschen genauso wie für Agents, besonders die **Produktprinzipien** (alles on-device, keine Fremdpakete, keine Telemetrie, Nutzerdaten abwärtskompatibel, nichts erfinden).
3. Für jede Verhaltensänderung einen Test, für jeden Bugfix einen Regressionstest.
4. Neue oder gelöschte Dateien: `python3 scripts/generate_project.py` ausführen und `project.pbxproj` mitcommitten. Das Xcode-Projekt nie von Hand bearbeiten.
5. `scripts/check.sh` muss lokal grün sein (Xcode 26 oder neuer, macOS 26 oder neuer).
6. `CHANGELOG.md` unter `[Unreleased]` ergänzen.
7. Commits nach [Conventional Commits](https://www.conventionalcommits.org/) auf Englisch (`fix: …`, `feat: …`).
8. Pull Request gegen `main` öffnen und die Vorlage ausfüllen.

Die CI startet bei Pull Requests von Erstbeitragenden erst nach Freigabe durch den Maintainer.

## Sprache

Code, Bezeichner und Commit-Nachrichten auf Englisch. Oberfläche und Dokumentation sind derzeit Deutsch. Issues und Pull Requests gern auf Deutsch oder Englisch.

## KI-Werkzeuge

Beiträge mit KI-Unterstützung sind willkommen; das Projekt entsteht selbst überwiegend so ([docs/AI.md](docs/AI.md)). Bitte gib im Pull Request an, ob und wie KI beteiligt war, und reiche nur Änderungen ein, die du verstehst und selbst getestet hast.

## Lizenz deiner Beiträge

Mit einem Pull Request erklärst du, dass du die Rechte an deinem Beitrag hast und dass er unter der [MIT-Lizenz](LICENSE) des Projekts veröffentlicht wird.

## Umgang miteinander

Es gilt der [Verhaltenskodex](CODE_OF_CONDUCT.md).
