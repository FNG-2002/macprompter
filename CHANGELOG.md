# Changelog

Alle nennenswerten Änderungen. Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/), Versionierung nach [Semantic Versioning](https://semver.org/lang/de/). Die App-Version steht zentral in `scripts/generate_project.py` (`MARKETING_VERSION`, Build-Nummer `CURRENT_PROJECT_VERSION`).

## [Unreleased]

### Hinzugefügt
- Spracherkennung in allen Sprachen, die Apples lokales Diktat auf dem Mac anbietet (auf macOS 26 zum Beispiel Französisch, Spanisch, Italienisch, Niederländisch, Polnisch, Türkisch und weitere), statt nur Deutsch und Englisch. Weiterhin vollständig auf dem Gerät; fehlt ein Sprachmodell, lädt macOS es beim ersten Take. Sprachen ohne Leerzeichen zwischen Wörtern (Japanisch, Chinesisch, Thai) sind noch nicht dabei.
- Sprachvorschlag: Ist ein Skript eindeutig in einer anderen Sprache geschrieben, bietet die Seitenleiste „Text klingt nach … · übernehmen“ an.
- Markierung im Sprechtempo vorziehen (Einstellungen → Lesen, standardmäßig an): Im Modus Stimme läuft die Markierung in deinem Tempo mit und liegt auf dem Wort, das du gerade sagst, statt etwa ein Wort hinter dir. Höchstens zwei Wörter voraus; bei Stille oder wenn du vom Skript abweichst, bleibt sie stehen und springt nie von selbst zurück.
- Update-Suche (standardmäßig an, abschaltbar unter Einstellungen → Über macprompter): Einmal am Tag fragt die App bei GitHub nach der neuesten Versionsnummer und zeigt in der Bibliothek einen Hinweis, wenn es eine neue Version gibt. Hilfe → „Nach Updates suchen …“ prüft sofort. Installiert wird nichts automatisch.
- Lesekomfort: Schriften als Kacheln mit den neuen Schriften Serif und Mono, schnelle Größen S/M/L/XL neben dem Regler und sechs Textfarben. Die Vorschau zeigt Schrift, Größe, Farbe und Markierung so, wie sie im Prompter erscheinen.

### Geändert
- Modus Stimme: Bereits gesprochener Text wird abgedunkelt, der Text, der noch kommt, bleibt hell. Das aktuelle Wort liegt auf einem halbtransparenten Kasten in der Akzentfarbe.
- Der Prompter wächst beim Einblenden aus der Notch und zieht sich beim Ausblenden zurück; der Countdown zählt animiert. Mit „Bewegung reduzieren“ wird nur kurz überblendet.
- Die Bibliothek zeigt Sprachen kurz („Deutsch“, „Englisch“), Varianten mit Region („Deutsch (Schweiz)“).
- Der MCP-Zugang akzeptiert alle Sprachcodes (z. B. `fr`, `tr`, `de-CH`) statt nur `de` und `en`.
- Entwicklung: Lokale Testversionen (`scripts/install.sh`) werden mit demselben Projektzertifikat signiert wie die Releases. Testversion und Release ersetzen sich gegenseitig, ohne dass macOS erneut nach Mikrofon oder Eingabeüberwachung fragt. Das Zertifikat wurde dafür neu ausgestellt; wer 1.0.0 installiert hat, bestätigt die Freigaben beim nächsten Update einmal neu.

### Behoben
- Die Seitenleiste wurde beim Wechsel des Modus kurz breiter, wenn Scrollbalken dauerhaft eingeblendet sind (z. B. mit angeschlossener Maus).
- Wörter aus zerlegt gespeicherten Umlauten (etwa aus kopierten Dateinamen) zerfielen in zwei Wörter und wurden von der Sprachsteuerung nicht erkannt.

## [1.0.0] – 2026-11-09

Die erste öffentliche Version: macprompter ist jetzt Open Source unter der MIT-Lizenz und als fertige App zum Herunterladen verfügbar. Gegenüber dem internen Stand 0.1.0 folgt die Sprachsteuerung deutlich schneller und genauer, dazu kommen PDF-Präsentationen mit automatischem Folienwechsel, Vorlagen, die iPhone-Fernbedienung (zum Selbstbauen), ein lokaler Zugang für KI-Assistenten und das Scrollrad als Steuerung in allen Modi.

### Highlights
- **Sprachsteuerung:** Apples Diktiermodell mit Namen und Fachbegriffen aus dem Skript liefert neue Wörter etwa viermal so oft wie zuvor; unterschiedliche Schreibweisen (Zahlen, Abkürzungen, Komposita) bremsen die Markierung nicht mehr.
- **Präsentationen:** PDF importieren, Sprechtext pro Folie, Folien wechseln mit dem Lesefortschritt, Referentenansicht, Aufdeck-Schritte; neu exportierte PDFs behalten ihre Texte.
- **Bedienung:** Scrollrad und Trackpad in allen Modi, auch über anderen Apps; Prompter-Größe per Ziehen; durchscheinender Hintergrund; Einstellungen pro Skript; `.macprompter`-Dateien zum Sichern und Teilen.
- **Für KI-Assistenten:** lokaler MCP-Zugang (standardmäßig aus), auch für Claude Desktop und Cowork.
- **Open Source:** MIT-Lizenz, Beitragsregeln, offengelegter KI-Einsatz ([docs/AI.md](docs/AI.md)), Releases automatisch aus GitHub Actions.

### Hinweise zum Update
- Neue App-Kennung `io.github.fng-2002.macprompter` (vorher eine persönliche Kennung). Für macOS ist das eine neue App: Selbst gebaute Vorversionen legten Skripte und Einstellungen in einem anderen Datenordner ab; sie müssen einmalig übernommen werden (z. B. als `.macprompter`-Dateien sichern und neu öffnen). Mikrofon und Eingabeüberwachung fragt macOS neu ab, die iPhone-Kopplung und der freigegebene MCP-Ordner sind neu einzurichten.
- Die App ist noch nicht von Apple notarisiert; den ersten Start bestätigst du unter Systemeinstellungen → Datenschutz & Sicherheit → „Dennoch öffnen“.

### Bekannte Grenzen
- Die Oberfläche ist nur auf Deutsch; Skripte und Spracherkennung gibt es auf Deutsch und Englisch.
- Automatische Tests laufen unter macOS 26 und 27, im Alltag erprobt auf Apple Silicon. Intel-Macs sind ungetestet.
- Die Sprachsteuerung wurde mit echtem Mikrofon bisher vor allem auf einem Mac und mit einer Stimme erprobt.
- Die iPhone-App ist nicht im App Store und muss mit Xcode selbst installiert werden.
- Der Aufnahmeschutz des Prompters ist keine Garantie gegen Bildschirmaufnahmen.

### Hinzugefügt
- Open Source unter der MIT-Lizenz mit `LICENSE`, `THIRD_PARTY_NOTICES.md`, `CONTRIBUTING.md`, `SECURITY.md`, Verhaltenskodex, Issue-Formularen und Offenlegung des KI-Einsatzes (`docs/AI.md`).
- Releases baut und veröffentlicht GitHub Actions aus einem Versions-Tag: Tests, universeller Build, Signatur mit stabilem Projektzertifikat, DMG mit SHA-256-Prüfsumme und Release-Notes aus diesem Changelog (`docs/RELEASING.md`).
- Neues README mit Demo-Video, Screenshots und Installationsanleitung.
- Hilfe-Menü mit „macprompter auf GitHub“, „Versionshinweise“, „Problem melden …“ und „Lizenzen und Danksagungen“. Die Links öffnen den Browser; die App selbst baut keine Verbindung auf.
- „Über macprompter“ (App-Menü) zeigt Copyright, MIT-Lizenz, GitHub-Link und die vollständigen Lizenztexte mitgelieferter Software Dritter. Einstellungen → Über macprompter nennt zusätzlich, wie die App mit KI-Coding-Agents entsteht.
- MCP für Claude Desktop und Cowork: Das mitgelieferte Hilfsprogramm `macprompter-mcp` spricht stdio und reicht alles an den lokalen MCP-Zugang der App weiter. Die fertige Konfiguration steht unter Einstellungen → KI-Agenten → Einrichten. Läuft macprompter nicht, startet der Helfer die App im Hintergrund. Eigene Sandbox, nur ausgehende Verbindungen zu `127.0.0.1`; die App selbst bekommt keine neue Berechtigung.
- Sprachdiagnose unter Einstellungen → Diagnose (vorher „Experimentell“): Zeitwerte des letzten Takes (Wortende → erkannt aus den Wortzeiten der finalen Ergebnisse, Takt neuer Wörter, verwendeter Erkenner, Rückkehr per Satzmodell, Erkennung, Wortzuordnung, Markierung als Median und p95, Ergebnisse ab einer Sekunde, Ereignisse ohne Fortschritt nach Grund, Audioblock, Start der Erkennung samt Mikrofonanteil). Nur Zahlen im Arbeitsspeicher, keine Wörter, kein Audio.
- Diktiererkennung mit Skriptvokabular: Apples Diktiermodell liefert neue Wörter etwa alle 0,25 s statt etwa einmal pro Sekunde und lernt Namen und Fachbegriffe aus dem Skript. Immer aktiv; ohne Diktiermodell für die Sprache gilt automatisch die einfache Erkennung.
- „Umformulierungen erkennen“ (semantische Rückkehr) läuft im Modus Stimme immer im Hintergrund; der Schalter entfällt. Gespeicherte Werte der entfernten Schalter werden ignoriert, alle übrigen Einstellungen bleiben erhalten.
- „Im Sprechtempo scrollen“ unter Einstellungen → Lesen → Prompter (Modus Stimme, standardmäßig aus): Der Text gleitet zwischen erkannten Wörtern in deinem Tempo weiter, höchstens drei bis vier Wörter voraus, stoppt bei Pausen und steigt stetig statt zeilenweise.
- Laufzeit zurücksetzen: kleiner Uhr-Knopf unten rechts im Prompter neben der Zeit und neben der Laufzeit in der Referentenansicht. Beide setzen beide Zeiten auf 00:00; Textposition, Folie und Start/Pause bleiben unverändert.
- `scripts/install.sh`: geprüfte Release-Version nach `/Applications` installieren, signiert mit einem vorhandenen „Apple Development“-Zertifikat, damit Freigaben wie Eingabeüberwachung und Mikrofon Updates überstehen. `--quick` baut nur eine ungeprüfte Testversion.
- Schalter „Folien wechseln mit dem Lesefortschritt“ unter Einstellungen → Steuerung → Folien (global, Standard an): Ausgeschaltet wechselt die Folie nicht mehr automatisch, wenn der Text an einer Folienmarke vorbeiläuft – egal ob per Stimme, Tempo, Scrollrad, Tasten oder iPhone. Manuelle Folienwechsel bleiben möglich.
- Scrollrad und Trackpad steuern den Prompter in allen Modi, auch ohne iPhone-App: über dem Prompter, wobei die Hover-Pause bestehen bleibt, und standardmäßig auch, wenn der Zeiger in einer anderen App liegt (dort scrollt das Fenster unter dem Zeiger mit). Abschaltbar unter Einstellungen → Steuerung → Scrollrad.
- Eigener Dateityp `.macprompter`: Ein Skript mit Folien, eingebetteter PDF und seinen Seitenleisten-Einstellungen in einer Datei sichern (⇧⌘S), teilen, per Doppelklick oder ⌘O wieder laden. Import legt immer ein neues Skript an. Per MCP mit `export_script` und `import_script`.
- Einstellungen pro Skript: Modus, Tempo, Schrift, Größe, Zeilenabstand, Lesezeile, Deckkraft, Position, Prompter-Größe und Referentenansicht merkt sich jedes Skript; beim Auswählen werden sie wiederhergestellt. Bildschirmwahl, Spiegelung und Countdown bleiben global.
- Zugang für KI-Agenten per MCP (#10): Claude & Co. legen Skripte und Präsentationen an und bearbeiten Sprechtexte pro Folie (Werkzeuge u. a. `create_presentation`, `set_slide_text`, `replace_presentation_pdf`). Streamable HTTP nur auf 127.0.0.1, Token, standardmäßig aus; neuer Einstellungsbereich „KI-Agenten“ mit Port, Token, fertigen Befehlen und freigegebenem PDF-Ordner. Löschen ist für Agenten nicht möglich.
- Größe des Prompters per Ziehen an den Seiten, an der Unterkante und an den unteren Ecken ändern (#9). An der Notch bleibt er zentriert, frei schwebend bleiben die gegenüberliegenden Kanten stehen. Maximal 1800 × 1000 pt (vorher 1000 × 600) für große Bildschirme.
- Vorlagen (#6): „Dein erster Take“, „A little introduction“ und „Quartalsupdate in 10 Folien“ (mitgelieferte PDF; Folie 3 deckt drei Punkte in drei Schritten auf). Ansehen und als eigenes Skript mit eigenem Namen übernehmen (Seitenleiste „Aus Vorlage …“, ⇧⌘N, leere Bibliothek).
- Einstellbare Deckkraft des Prompter-Hintergrunds (20–100 %) unter Lesekomfort und Einstellungen → Lesen (#8). Der Text bleibt voll deckend.
- iOS-App: Die Scrollfläche „Manuell scrollen“ lässt sich im Vollbild öffnen (#7) – große Wischfläche, breite Schritt-Tasten, Start/Pause und Statuszeile; der Bildschirm bleibt dabei an.
- iPhone-Fernbedienung (#2): neue iOS-App **macprompter Remote** (iOS 26, Liquid Glass) für Start, Pause, Ausblenden, Skriptwahl, Modus, Tempo, manuelles Scrollen und PDF-Folien, mit wählbarem Layout (Alles, Tempo und Text, Nur Folien). Nur lokales Netz bzw. Peer-to-Peer-WLAN über Bonjour, TLS mit Schlüssel pro Gerät, Kopplung per sechsstelligem Code. Am Mac standardmäßig aus (Einstellungen → iPhone-Fernbedienung, mit Geräteliste und Widerruf). Details: `docs/REMOTE.md`.
- PDF-Präsentationen (#3): PDF importieren (⇧⌘O) oder mit einem Skript verknüpfen. Folien-Editor mit Text pro Folie oder Foliengruppe, Thumbnails, Gruppieren/Lösen. Jeder Abschnitt beginnt mit `[Start · Folie n]` und endet mit `[Nächste Folie]`, in Gruppen wechselt `[Weiter]` die Seite.
- Foliensynchronisation: Folien wechseln mit gesprochenem Text bzw. mit der Fokuszeile. Manuelle Wechsel per Pfeiltasten, Presenter-Fernbedienung oder ⌥⌘←/→ lassen den Prompter mitspringen; Hover und Countdown haben Vorrang.
- Präsentationsmodus (⌘↩): Vollbild-Folien auf wählbarem Bildschirm, Referentenansicht mit aktueller/nächster Folie und Laufzeit auf dem zweiten Bildschirm, Schwarzbild (B), Esc beendet.
- Neu exportierte PDFs werden automatisch erkannt (Security-Scoped Bookmark auf das Original, Kopie in der Bibliothek). Texte bleiben ihren Folien zugeordnet, auch wenn Seiten eingefügt, entfernt, verschoben oder bearbeitet werden; neue und geänderte Folien werden markiert.
- Agent-Grundlagen: `AGENTS.md`/`CLAUDE.md`, `docs/ARCHITECTURE.md`, `docs/DECISIONS.md`, dieser Changelog.
- `scripts/check.sh` als einheitliche Prüfung (Build + Tests, optional Release-Build mit Signaturprüfung); findet Xcode auch, wenn `xcode-select` auf die Command Line Tools zeigt.
- GitHub-CI (`macos-26`) für Pull Requests und `main`, PR- und Issue-Vorlagen.

### Geändert
- Version 1.0.0. App, iOS-App und MCP-Helfer übernehmen Version und Build-Nummer aus einer Stelle im Projektgenerator.
- Die synthetischen Testaudios werden mit `scripts/make_fixtures.sh` lokal erzeugt statt eingecheckt, weil Apples Lizenz die Veröffentlichung der Systemstimmen nicht erlaubt (ADR-24). `scripts/check.sh` erledigt das automatisch.
- Mikrofon-Audio geht in Blöcken der Gerätegröße (typisch ~10 ms) über einen `AVAudioSinkNode` an die Erkennung statt in ~100-ms-Blöcken des bisherigen Taps; jedes Wort wartete dort bis zu 100 ms, bevor der Erkenner es bekam. Lehnt ein Gerät den neuen Weg ab, gilt automatisch der bisherige. Die Pegelanzeige im Overlay aktualisiert höchstens 30-mal pro Sekunde.
- Wechselt der Mikrofoneingang während eines Takes (z. B. AirPods verbinden sich), läuft die Sprachsteuerung mit dem neuen Eingang weiter, statt mit einer Fehlermeldung abzubrechen.
- Halbe Wörter am Ende eines Teilresultats („wie moderne Spei“) halten die Markierung nicht mehr auf: Die vollständigen Wörter davor werden sofort markiert, und die spätere Korrektur zum ganzen Wort zählt.
- Sprachführung bleibt dran, wenn der Erkenner anders schreibt als das Skript: Zahlen („drei“ ↔ „3“, „25“ ↔ „fünfundzwanzig“, „112“ ↔ „one hundred twelve“), Prozentzeichen, Abkürzungen („Dr.“, „z. B.“, „etc.“), Bindestriche und Komposita („email“ ↔ „E-Mail“), englische Kurzformen und knapp verfehlte Wortendungen nahe der Leseposition („Speichern“ → „Speicher“). Bisher hing die Markierung in solchen Fällen ein bis drei Wörter hinterher.
- Hover sperrt das Scrollrad nicht mehr (bisher konnte das Scrollrad dadurch nie wirken); Timer, Sprache, Tastatur und Countdown bleiben während Hover gesperrt. Die Scrollrichtung folgt jetzt der Systemeinstellung wie in jedem anderen Fenster, ein Mausrad-Raster bewegt eine Zeile.
- ⇧⌘S sichert jetzt als macprompter-Datei; der Text-Export heißt „Als Text exportieren …“.
- Neue Installationen starten mit leerer Bibliothek statt mit Beispielskripten (#6); bestehende Bibliotheken bleiben unverändert.
- Folien werden nach Abschnitten nummeriert: Mehrere PDF-Seiten einer Folie (Aufdecken) heißen „Folie 3 · 3 Schritte“ statt „Folien 3–5“. Referentenansicht, Overlay und iPhone zeigen „Folie 3 von 10 · Schritt 2/3“. Gespeicherte Präsentationen werden beim Laden automatisch angepasst.
- Neues Entitlement `com.apple.security.files.bookmarks.app-scope` für die Verknüpfung mit der Original-PDF (ADR-8).
- Neues Entitlement `com.apple.security.network.server` und `NSBonjourServices`/`NSLocalNetworkUsageDescription` für die Fernbedienung (ADR-9). Nur der Debug-Build (Test-Host) hat zusätzlich `network.client`.
- `scripts/check.sh` baut zusätzlich die iOS-App für den Simulator, mit `--release` auch für Geräte (ohne Signatur). `scripts/MakeIcon.swift --ios` erzeugt das iOS-Icon.

### Behoben
- Release-Builds von App und MCP-Helfer enthielten die Debug-Berechtigung `get-task-allow` (Debugger durfte sich anhängen); sie ist jetzt nur noch in Debug-Builds gesetzt.
- Einstellungen → Über macprompter zeigte fest „Version 0.1.0“ statt der tatsächlichen Version.
- Scrollen außerhalb des Prompters wirkte nur über Fenstern anderer Apps mit Scrollbereich, nicht über anderen Flächen und nicht über der Präsentation. Ein mitlesender Event-Tap erfasst jetzt jedes Scroll-Ereignis; Bibliothek, Editor und Einstellungen scrollen weiter nur sich selbst.
- Im Sprachmodus wechselte die Folie nicht, wenn man mit Scrollrad, Tasten oder iPhone an einer Folienmarke vorbeiscrollte. Jetzt gilt das in allen Modi, gesteuert nur über „Folien wechseln mit dem Lesefortschritt“.
- Scrollen außerhalb des Prompters wirkte nicht: macOS liefert Scroll-Ereignisse anderer Apps nur mit der Freigabe „Eingabeüberwachung“. macprompter fragt sie beim Einblenden des Prompters an (nur bei eingeschalteter Option), zeigt in den Einstellungen einen Hinweis mit Knopf zu den Systemeinstellungen und übernimmt eine neue Freigabe beim Zurückkehren in die App.
- Einstellungen → KI-Agenten: Der Token wurde abgeschnitten. Er steht jetzt vollständig in einer eigenen Zeile, mit Symbolen zum Anzeigen und Kopieren; Kopieren-Knöpfe bestätigen kurz mit einem Haken.
- Größe ziehen blieb unzuverlässig: Das Panel folgte dem Drag verzögert, und die Mausposition wurde relativ zum mitwandernden Fenster berechnet, dadurch ruckelte oder sprang die Größe. Beim Herausziehen aus dem Panel endete zudem kurz die Hover-Pause. Jetzt bleibt die Hover-Pause während des Ziehens bestehen, das Panel folgt sofort, und die Mausposition kommt direkt vom System.
- Größe des Prompters ziehen funktionierte nicht zuverlässig: Frei schwebend verschob ein Griff das ganze Fenster, und weil das Panel nie aktiv wird, erschien kein Größen-Cursor. Griffe jetzt breiter (10 pt), mit eigenem Cursor und sichtbarem Ziehgriff unten in der Mitte.
- Der Projektgenerator übernahm versteckte Dateien wie `.DS_Store` aus `Resources` als App-Ressource ins Bundle.
- Ein Scrolltest hing von der Systemeinstellung „Bewegung reduzieren“ des Testrechners ab; die Abfrage ist jetzt injizierbar.

## [0.1.0] – 2026-10-05

Erster interner Stand, noch nicht veröffentlicht.

### Hinzugefügt
- Skriptbibliothek mit atomarem Speichern, Suche, Duplizieren, TXT-/Markdown-/RTF-Import und TXT-Export.
- Nicht aktivierendes Overlay an der Notch oder frei schwebend, Bildschirmwahl, Spaces-/Vollbild-Unterstützung.
- Modi Automatisch, Manuell und Stimme (Apple SpeechAnalyzer, Deutsch/Englisch, lokal).
- Hover-Pause über eine zentrale Bewegungssperre; Regieanweisungen in eckigen Klammern.
- Schriften System, Rund und OpenDyslexic; Spiegelung, Fokuszeile, Countdown, Menüleiste, globale Tastenkürzel.
- Sprachführung mit lokalem Anker, Einschub-Erkennung und toleranter lokaler Rückkehr (24.09.2026).
- Experimentelle semantische Rückkehr mit Apple `NLEmbedding`, standardmäßig aus (24.09.2026).
- In-Memory-Latenzdiagnose ohne Audio-/Transkriptspeicherung.

### Geändert
- Scrollen über einen Display-Link am jeweiligen Bildschirm statt 60-Hz-Timer; entfernungsabhängige Glättung (05.10.2026).
- Vorbereiteter Skriptindex für die semantische Kandidatensuche; identische Transkripte verwerfen keine laufenden Anfragen (05.10.2026).
