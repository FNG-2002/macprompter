# Releases

Releases baut und veröffentlicht GitHub Actions ([`.github/workflows/release.yml`](../.github/workflows/release.yml)). Lokal muss nichts hochgeladen werden. Ein Release entsteht nur auf ausdrücklichen Wunsch des Maintainers.

## Ablauf

1. **Release-PR** (Branch `chore/release-x.y.z`; eine kleine Korrektur darf im selben PR wie das Release kommen, das spart CI-Läufe):
   - `MARKETING_VERSION` in `scripts/generate_project.py` erhöhen, `CURRENT_PROJECT_VERSION` (Build-Nummer) um 1 erhöhen, `python3 scripts/generate_project.py`.
   - In `CHANGELOG.md` den Inhalt von `[Unreleased]` in einen neuen Abschnitt `## [x.y.z] – JJJJ-MM-TT` verschieben und Release-Notes schreiben (siehe unten). `[Unreleased]` bleibt leer stehen.
   - `docs/VALIDATION.md`: datierter Abschnitt mit Testanzahl und dem, was manuell offen ist.
   - `scripts/check.sh --release` lokal grün, PR mergen.
2. **Tag setzen** auf dem gemergten `main`, sobald CI auf `main` grün ist (`gh run list --branch main --limit 1`); dann übernimmt der Release-Workflow dieses Ergebnis statt erneut zu testen (ADR-32):
   ```sh
   git switch main && git pull --ff-only
   python3 scripts/release_notes.py --check vX.Y.Z
   git tag -a vX.Y.Z -m "macprompter X.Y.Z" && git push origin vX.Y.Z
   ```
3. **GitHub Actions** prüft, dass Tag, App-Version und CHANGELOG zusammenpassen und der Tag auf `main` liegt, führt alle Tests aus, sofern CI denselben Commit nicht schon grün getestet hat, baut die universelle Release-App, signiert sie, packt `macprompter-X.Y.Z.dmg` samt SHA-256-Prüfsumme und veröffentlicht das GitHub-Release mit den Notes aus dem CHANGELOG. Dauer etwa 10 Minuten: `gh run watch`.
4. **Kontrolle:** Release-Seite ansehen, DMG herunterladen, installieren, starten (`docs/VALIDATION.md`, „Auf einem echten Mac prüfen“).

Ein manueller Lauf (`gh workflow run release.yml`) und Pull Requests, die die Release-Pipeline ändern, bauen nur eine Test-DMG als Workflow-Artefakt und veröffentlichen nichts.

Den Abschnitt in `docs/VALIDATION.md` schreibt man vor dem Tag; die Kontrolle nach der Veröffentlichung wird mit dem nächsten PR nachgetragen statt mit einem eigenen.

## Release-Notes: Mindestanforderungen

Jeder Versionsabschnitt im CHANGELOG ist gleichzeitig die Release-Beschreibung auf GitHub. Der Workflow bricht ab, wenn er fehlt oder zu dünn ist. Pflicht:

- **Zusammenfassung** als erster Absatz (mindestens ein ganzer Satz): Was bringt diese Version, für wen ist sie wichtig?
- Listen unter `### Hinzugefügt`, `### Geändert`, `### Behoben`, bei Bedarf `### Entfernt` und `### Sicherheit`. Aus Nutzersicht formulieren, nicht als Commit-Liste.
- **Hinweise zum Update**, wenn sich etwas für bestehende Nutzer ändert (neue Berechtigung, geänderte Einstellung, Datenformat).
- **Bekannte Grenzen**, wenn eine neue Funktion nur teilweise geprüft ist (z. B. „mit echtem Mikrofon nur auf einem Mac getestet“).

Installationsanleitung, Gatekeeper-Hinweis, Systemvoraussetzungen und Prüfsumme hängt `scripts/release_notes.py` automatisch an. Vorschau: `python3 scripts/release_notes.py --notes self-signed`.

## Versionierung

[Semantic Versioning](https://semver.org/lang/de/): `x.Y.z` für neue Funktionen, `x.y.Z` für Korrekturen, `X.y.z` für Änderungen, die bestehende Nutzer zu einer Anpassung zwingen. Die Build-Nummer steigt mit jedem Release.

## Signatur

`scripts/package_release.sh` wählt die stärkste verfügbare Signatur:

| Stufe | Secrets im Repository | Ergebnis für Nutzer |
| --- | --- | --- |
| Developer ID + Notarisierung | `MACOS_DEVELOPER_ID_P12`, `MACOS_DEVELOPER_ID_P12_PASSWORD`, `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_PASSWORD` | startet ohne Warnung |
| Eigenes Zertifikat (aktuell) | `MACOS_SIGNING_P12`, `MACOS_SIGNING_P12_PASSWORD` | erster Start über „Dennoch öffnen“; Freigaben bleiben bei Updates erhalten |
| Ad hoc | keine (z. B. in Forks) | erster Start über „Dennoch öffnen“; Freigaben nach jedem Update neu |

**Eigenes Zertifikat:** ein selbst ausgestelltes Code-Signing-Zertifikat „macprompter Release Signing“ (RSA 2048, 10 Jahre gültig). Es liegt als Secret im Repository und im Anmelde-Schlüsselbund des Maintainers; auf dem Runner wird es für die Signatur als vertrauenswürdig markiert, der Runner wird danach verworfen. Weil macOS Freigaben (Mikrofon, Eingabeüberwachung) und den Sandbox-Container an das Zertifikat bindet statt an den einzelnen Build, überstehen sie Updates. Geht das Zertifikat verloren oder wird es ersetzt, fragt macOS nach dem nächsten Update einmal neu. Angelegt bzw. ersetzt wird es mit `scripts/make_signing_identity.sh` (vom Maintainer auszuführen, `--replace` zum Ersetzen). Das Skript erzeugt Schlüssel und Zertifikat in einem temporären Ordner, speichert beides als Secrets und im Anmelde-Schlüsselbund (dort für Code-Signatur vertrauenswürdig, macOS fragt einmal nach dem Passwort) und löscht die Dateien wieder.

**Eine App für Tests und Releases:** `scripts/install.sh` signiert lokale Testversionen bevorzugt mit demselben Zertifikat. Testversion und Release haben dadurch dieselbe Kennung, denselben Datenordner und dieselbe Signatur; sie ersetzen sich gegenseitig in `/Applications`, ohne dass macOS erneut nach Freigaben fragt (ADR-28). Beim ersten Signieren fragt macOS eventuell, ob `codesign` den Schlüssel verwenden darf: „Immer erlauben“.

**Umstieg auf Developer ID** (bezahlte Apple-Developer-Mitgliedschaft): „Developer ID Application“-Zertifikat als `.p12` exportieren und als `MACOS_DEVELOPER_ID_P12`/`…_PASSWORD` hinterlegen, für die Notarisierung ein app-spezifisches Passwort der Apple-ID als `NOTARY_PASSWORD` sowie `NOTARY_APPLE_ID` und `NOTARY_TEAM_ID`. Der Workflow nutzt dann automatisch Developer ID und notarisiert die DMG. Einmalig fragt macOS nach dem Update erneut nach den Freigaben.

## Was bewusst fehlt

- **Update-Hinweis statt automatischer Installation** (ADR-29). Ab 1.1.0 vergleicht die App täglich ihre Version mit dem neuesten Release über die GitHub-API; Entwürfe und Vorabversionen zählen nicht. Ein Release erscheint also bei allen Nutzern mit eingeschalteter Update-Suche spätestens am nächsten Tag als Hinweis. Installiert wird nicht; echtes Auto-Update bräuchte Sparkle (Fremdpaket). Der Skill `macos-release` beschreibt einen Sparkle-Ablauf und ist für dieses Projekt nur für DMG und Notarisierung relevant.
- **Keine iOS-App als Download.** iOS-Apps lassen sich nur über App Store oder TestFlight verteilen. **macprompter Remote** bleibt vorerst Quellcode zum Selbstbauen.

## Fehlerbehebung

- **Workflow bricht bei „Tag, version and release notes agree“ ab:** Version im Generator, Tag und CHANGELOG-Abschnitt angleichen. Den falschen Tag löschen (`git push origin :refs/tags/vX.Y.Z`, `git tag -d vX.Y.Z`), korrigieren, neu taggen. Ein bereits veröffentlichtes Release wird nicht überschrieben, sondern mit einer neuen Patch-Version ersetzt.
- **Signatur schlägt fehl:** Secrets prüfen (`gh secret list`); ohne Secrets signiert der Workflow ad hoc und meldet das im Log.
