# Entscheidungen (ADR-Log)

Kurze, dauerhaft gültige Architektur- und Produktentscheidungen. Neue Einträge unten anhängen, fortlaufend nummerieren. Überholte Einträge nicht löschen, sondern mit „Ersetzt durch ADR-n“ markieren.

Format: **Kontext** · **Entscheidung** · **Konsequenzen**.

## ADR-1 · Alles on-device, keine Telemetrie (23.09.2026)

- **Kontext:** Teleprompter-Skripte und Sprache sind persönlich; Nutzung oft in Meetings.
- **Entscheidung:** Keine Netzwerkzugriffe der App, keine Cloud-Erkennung, kein Account, keine Telemetrie. Sprachmodelle installiert macOS über `AssetInventory`.
- **Konsequenzen:** Erkennungsqualität ist auf Apples lokale Modelle begrenzt. Funktionen, die einen Server bräuchten (Sync, iPhone-Fernsteuerung über Cloud), sind ausgeschlossen bzw. nur lokal umsetzbar.

## ADR-2 · Keine externen Abhängigkeiten, generiertes Xcode-Projekt (23.09.2026)

- **Kontext:** Kleine App, lange Wartbarkeit, reproduzierbare Builds ohne Paketauflösung.
- **Entscheidung:** Keine Swift-Pakete oder Fremdmodelle. `MacPrompter.xcodeproj` wird von `scripts/generate_project.py` mit stabilen IDs erzeugt.
- **Konsequenzen:** Neue Dateien erfordern einen Generatorlauf. Build-Einstellungen werden im Skript geändert, nicht in Xcode.

## ADR-3 · Wortausrichtung als begrenzte gewichtete Sequenzsuche statt Modell (24.09.2026)

- **Kontext:** Sprachführung muss schnell und nachvollziehbar sein; eine Sekunde gefühlte Verzögerung ist zu lang.
- **Entscheidung:** Lokaler Anschluss mit dauerhaftem Anker, affine Lückenkosten, strengere globale Evidenz. Kein HMM-Training, kein LLM im Wortpfad.
- **Konsequenzen:** Freie Paraphrasen werden nicht zuverlässig erkannt. Schwellen sind Heuristiken mit Szenariotests. Details: [SPEECH_FOLLOWING.md](SPEECH_FOLLOWING.md).

## ADR-4 · Semantische Rückkehr nur optional mit Apple `NLEmbedding` (24.09.2026) – ersetzt durch ADR-22

- **Kontext:** Umformulierte Passagen finden keinen Wortanschluss.
- **Entscheidung:** Apple-Satzembeddings als experimentelle, standardmäßig ausgeschaltete Ergänzung – ausschließlich bei fehlgeschlagener Wortzuordnung, asynchron, mit 250-ms-Verfallsgrenze.
- **Konsequenzen:** Der normale Pfad wartet nie auf das Modell. Fremdmodelle (z. B. MiniLM) erst nach nachgewiesenem Mehrwert und neuer Entscheidung. Details: [SEMANTIC_RECOVERY.md](SEMANTIC_RECOVERY.md).

## ADR-5 · Display-Link als einzige Bewegungsuhr (05.10.2026)

- **Kontext:** Ein fester 60-Hz-Timer konkurrierte mit der Bildwiederholrate und löste unnötige SwiftUI-Updates aus.
- **Entscheidung:** Der Reader treibt die Bewegung über einen `CADisplayLink` an seinem Bildschirm; Offsets gehen direkt an `NSClipView`.
- **Konsequenzen:** Keine zweite Uhr einführen. Zeitabhängige Logik nimmt `dt` entgegen und bleibt so deterministisch testbar. Details: [RENDERING_OPTIMIZATION.md](RENDERING_OPTIMIZATION.md).

## ADR-6 · Aufnahmeschutz ehrlich als Best Effort (23.09.2026)

- **Kontext:** `NSWindow.sharingType = .none` wird von ScreenCaptureKit nicht garantiert respektiert.
- **Entscheidung:** Flag setzen, aber keine „unsichtbar“-Versprechen, keine privaten WindowServer-APIs.
- **Konsequenzen:** README und Einstellungen weisen auf die Grenze hin; Nutzer testen ihre Meeting-App selbst.

## ADR-7 · Autonomer Agent-Workflow (25.10.2026)

- **Kontext:** Das Projekt wurde bisher interaktiv entwickelt und soll künftig von Coding-Agents ohne Rückfragen weitergeführt werden.
- **Entscheidung:** Verbindliche Regeln in [AGENTS.md](../AGENTS.md). Jede Anforderung auf eigenem Branch, `scripts/check.sh` als Definition of Done, PR mit CI auf `macos-26`, Squash-Merge durch den Agent. Commits in Conventional Commits (Englisch), Doku und UI auf Deutsch.
- **Konsequenzen:** Die Historie bleibt pro Anforderung nachvollziehbar. CI läuft nur für PRs/manuell, um das macOS-Minutenkontingent des privaten Repos zu schonen. Manuell nicht automatisierbare Prüfungen werden explizit als offen markiert.

## ADR-8 · PDF-Präsentationen: abgeleiteter Skripttext, Fingerabdruck-Zuordnung, Bookmark (26.10.2026)

- **Kontext:** Issue #3 verlangt Text pro Folie bzw. Foliengruppe, Foliensynchronisation, Vollbild-/Referentenmodus und robuste Updates einer PDF, die noch in Arbeit ist.
- **Entscheidung:** Abschnitte mit Seiten-IDs sind die Quelle. `Script.body` wird daraus mit Cues abgeleitet, damit Reader, Sprachführung und Bewegungssperre unverändert bleiben. Seiten werden über Text und Bild-Hash wiedererkannt, nicht über die Seitennummer: reihenfolgetreue Ausrichtung, dann verschobene Folien, dann positionsgleiche bearbeitete Folien. Kein Text wird automatisch verworfen. Die App hält eine Kopie der PDF und ein Security-Scoped Bookmark auf das Original. Das Entitlement `com.apple.security.files.bookmarks.app-scope` wurde vom Maintainer freigegeben. Folien werden nur in der eigenen PDF-Ansicht synchronisiert, nicht in Keynote oder PowerPoint.
- **Konsequenzen:** `scripts.json` bleibt abwärtskompatibel (`presentation` optional). Neu exportierte PDFs werden beim Aktivieren der App bzw. vor dem Präsentieren übernommen, nie während einer laufenden Präsentation. Die Zuordnung ist eine Heuristik mit Szenariotests; geänderte und neue Folien werden zum Prüfen markiert. Details: [PRESENTATIONS.md](PRESENTATIONS.md).

## ADR-9 · Lokale iPhone-Fernbedienung als eng begrenzte Netzwerkausnahme (26.10.2026)

- **Kontext:** Issue #2 verlangt eine native iPhone-App zur Steuerung des Prompters. ADR-1 schließt Netzwerkzugriffe aus; eine Fernsteuerung braucht aber eine Verbindung zwischen zwei eigenen Geräten.
- **Entscheidung:** Ergänzung zu ADR-1: Die Mac-App darf – nur wenn der Nutzer es in den Einstellungen einschaltet – einen lokalen Dienst anbieten (Network.framework, Bonjour `_macprompter._tcp`, `includePeerToPeer`, `acceptLocalOnly`). Kein Internet, keine Cloud, keine Relays, keine Telemetrie. Freigegeben vom Maintainer: Entitlement `com.apple.security.network.server`; `network.client` nur im Debug-Build als Test-Host für den Loopback-Test. Verschlüsselung per TLS mit Pre-Shared Key pro Gerät; Kopplung über einen sechsstelligen Code (2 Minuten, 5 Versuche), PBKDF2-gestreckt, plus X25519-Vereinbarung, damit der 256-Bit-Geräteschlüssel nie übertragen wird. Datensparsamkeit: Das iPhone erhält nur Skripttitel und Status, keine Skripttexte, kein Audio, keine Transkripte. Alle Befehle laufen über `PrompterSession`, die `PlaybackGate` behält Vorrang. Gemeinsamer Protokollcode in `Shared/`, in beide Apps kompiliert und in der macOS-Suite getestet; eigene iOS-Testsuite vorerst nicht.
- **Konsequenzen:** Vorgabe war TLS 1.3-PSK; Network.framework verhandelt mit externem PSK gemessen nur TLS 1.2 `TLS_PSK_WITH_AES_128_GCM_SHA256` – ohne Forward Secrecy. Der kurze Code ist kein PAKE: Ein aktiver Angreifer im lokalen Netz während der Kopplung bleibt ein Restrisiko. Geräteschlüssel liegen am Mac im Sandbox-Container statt im Schlüsselbund (Ad-hoc-Signatur). Details und Messung: [REMOTE.md](REMOTE.md).

## ADR-10 · Vorlagen statt Testdaten, Folien mit Schritten (26.10.2026)

- **Kontext:** Issue #6: Die App startete mit zwei Beispielskripten in der eigenen Bibliothek. Gewünscht sind Beispiele zum Ansehen und Übernehmen, darunter eine Präsentation, deren Folie 3 drei Punkte aufdeckt und „trotzdem Folie 3“ bleibt.
- **Entscheidung:** Neue Bibliotheken starten leer. Eine Vorlagen-Galerie (`ScriptTemplate`, `TemplateGallery`) zeigt mindestens drei Beispiele und kopiert sie als unabhängige Skripte; die Beispiel-PDF liegt im App-Bundle und wird mit `scripts/MakeSampleDeck.swift` reproduzierbar erzeugt. Folien werden nach Abschnitten nummeriert, mehrere PDF-Seiten eines Abschnitts sind Schritte. Bestehende Bibliotheken werden nicht verändert; nur der abgeleitete Text gespeicherter Präsentationen wird beim Laden neu erzeugt.
- **Konsequenzen:** Ältere iPhone-Apps zeigen weiterhin Seitenzahlen (neue Felder in `RemoteSlides` sind optional). Vorlagen-Präsentationen haben kein Original zum Beobachten; „Neue PDF-Version wählen …“ verknüpft eine eigene Datei.

## ADR-11 · Agenten-Zugang als MCP-Server in der App (26.10.2026)

- **Kontext:** Issue #10: Agenten wie Claude sollen Skripte und Präsentationen mit Text pro Folie anlegen und bearbeiten. Vorgabe: Best Practice, ohne Fremdabhängigkeiten.
- **Entscheidung:** MCP über Streamable HTTP direkt in der App, nur auf 127.0.0.1, mit Bearer-Token, standardmäßig aus. Kein separates CLI: Es würde `scripts.json` parallel zur App schreiben (Datenverlust) und an der Sandbox scheitern. Kein stdio-Hilfsprogramm: Es bräuchte ein eigenes Target mit Netzwerkzugriff. HTTP-Parser und JSON-RPC sind minimal selbst implementiert, keine Pakete. PDFs liest die App nur aus einem vom Nutzer freigegebenen Ordner (Security-Scoped Bookmark) oder als Base64. Agenten können nicht löschen.
- **Konsequenzen:** Kein neues Entitlement (nutzt `network.server` aus ADR-9). macprompter muss laufen, solange ein Agent arbeitet. Jedes lokale Programm mit dem Token hat Zugriff auf die Skripttexte; das steht in den Einstellungen. Details: [MCP.md](MCP.md).

## ADR-12 · Eigener Dateityp `.macprompter`, Einstellungen pro Skript (26.10.2026)

- **Kontext:** Skripte samt Präsentation sollen gesichert, versendet und wieder geladen werden können, inklusive der Einstellungen aus der Seitenleiste, auch per MCP.
- **Entscheidung:** Eine einzelne JSON-Datei mit `format`/`version`, dem `Script` (inklusive Folien und `settings`) und der PDF als Base64. Eine Datei lässt sich mailen und per AirDrop teilen; ein Paket-Ordner oder ZIP ginge nicht ohne Zusatzaufwand bzw. Fremdbibliothek. Bookmarks auf Dateien des Absenders werden nie mitgegeben. Import legt immer ein neues Skript mit neuen IDs und eigener PDF-Kopie an; passt die PDF nicht exakt zu den Folien, wird über `SlideMatcher` neu zugeordnet. Seitenleisten-Einstellungen gehören zum Skript (`Script.settings`); maschinenabhängige Werte (Bildschirme), Spiegelung und Countdown bleiben global.
- **Konsequenzen:** Neuere Dateiversionen werden mit Hinweis abgelehnt, unbekannte oder fehlende Einstellungswerte fallen auf Standardwerte zurück und werden begrenzt. `scripts.json` bleibt abwärtskompatibel (`settings` optional). Base64 vergrößert Präsentationsdateien um etwa ein Drittel.

## ADR-13 · Scrollrad wirkt auch während Hover und außerhalb des Prompters (27.10.2026)

- **Kontext:** Der Maintainer wünscht manuelles Scrollen per Mausrad in jedem Modus, auch ohne iPhone-App, ausdrücklich auch dann, wenn der Zeiger nicht auf dem Prompter liegt; liegt er darauf, soll die Hover-Pause bleiben. Bisher sperrte Hover auch das Scrollrad. Da Scroll-Ereignisse nur bei Zeiger über dem Fenster ankommen, war das Scrollrad dadurch wirkungslos.
- **Entscheidung:** `PlaybackGate.allowsScrolling` (sichtbar, kein Countdown) als eigene Stufe der weiterhin einzigen Sperre. Das Scrollrad ist eine bewusste Geste, Hover bleibt für Timer, Sprache, Tastatur und Countdown verbindlich; nach Hover geht es an der gescrollten Stelle weiter, im Sprachmodus setzt die Wortausrichtung dort neu auf. Außerhalb des Prompters liefert ein globaler `NSEvent`-Monitor die Scroll-Ereignisse anderer Apps. Er besteht nur, solange der Prompter sichtbar ist, braucht keine Bedienungshilfen-Freigabe und kein Entitlement und kann Ereignisse nicht abfangen: Das Fenster unter dem Zeiger scrollt mit. Deshalb ist er in den Einstellungen abschaltbar (Standard an, weil ausdrücklich gewünscht). Fenster der eigenen App (Bibliothek, Editor) scrollen weiter nur sich selbst. Richtung wie `NSScrollView` (natürliches Scrollen wird respektiert), ein Raster = Schriftgröße + Zeilenabstand.
- **Konsequenzen:** `preferences.v1` erhält das optionale Feld `scrollAnywhere` (fehlend = an). Wer in anderen Apps scrollt, während der Prompter sichtbar ist, bewegt ihn mit. Fernbefehle vom iPhone bleiben unter Hover gesperrt.

## ADR-14 · Eingabeüberwachung für das Scrollrad außerhalb des Prompters (27.10.2026)

- **Kontext:** ADR-13 ging davon aus, dass ein globaler `NSEvent`-Monitor für Scroll-Ereignisse keine Berechtigung braucht. Auf macOS 27 prüft der WindowServer dafür `kTCCServiceListenEvent` (Eingabeüberwachung); ohne Freigabe kommen keine Ereignisse an. Der Maintainer hat die neue Berechtigung am 27.10.2026 freigegeben.
- **Entscheidung:** Kein Entitlement, nur die TCC-Freigabe. `CGRequestListenEventAccess()` wird angefragt, wenn der Prompter mit eingeschalteter Option erscheint (macOS fragt nur einmal); die Einstellungen zeigen fehlende Freigabe mit Knopf zu Datenschutz → Eingabeüberwachung. Beim Aktivieren der App wird der Status neu gelesen und der Monitor nach einer neuen Freigabe neu angelegt. Gelesen werden nur Scroll-Ereignisse, keine Tasten. Der Test-Host fragt nie an (`AppModel.isTestHost`), damit Testläufe keine Systemeinstellungen öffnen.
- **Konsequenzen:** Mit Ad-hoc-Signatur verliert macOS die Freigabe bei jeder neu gebauten Version; sie muss dann erneut erteilt werden. Über dem Prompter funktioniert das Scrollrad immer ohne Freigabe. Ob ein Neustart nach der Freigabe nötig ist, ist nicht automatisch geprüft; der Hinweis nennt ihn als Ausweg.

## ADR-15 · Lokale Installation mit Development-Signatur (27.10.2026)

- **Kontext:** Bei Ad-hoc-Signatur bindet macOS Datenschutz-Freigaben an den `cdhash` des Builds. Nach jeder neuen Installation galt die erteilte Eingabeüberwachung nicht mehr (Systemprotokoll: „Failed to match existing code requirement“), obwohl sie in den Systemeinstellungen weiter als erlaubt erschien.
- **Entscheidung:** Projekt und CI bleiben ad hoc. `scripts/install.sh` baut und prüft mit `scripts/check.sh --release` und signiert nur die installierte Kopie mit dem ersten „Apple Development“-Zertifikat im Schlüsselbund neu, mit denselben Entitlements und Hardened Runtime. Die Anforderung lautet dann Bundle-ID + Zertifikat, Freigaben überstehen Updates. Ohne Zertifikat bleibt es ad hoc.
- **Konsequenzen:** Beim Wechsel von ad hoc zur Development-Signatur müssen Freigaben einmal neu erteilt werden. Keine Distribution: Development-signierte Apps laufen nur auf diesem Mac zuverlässig; für Weitergabe braucht es weiterhin Developer ID und Notarisierung.

## ADR-16 · Event-Tap statt globalem NSEvent-Monitor für das Scrollrad (27.10.2026)

- **Kontext:** Der globale `NSEvent`-Monitor aus ADR-13 bekam nur Scroll-Ereignisse, die macOS an ein scrollbares Fenster einer anderen App ausliefert. Über nicht scrollbaren Flächen und über den eigenen Präsentationsfenstern – dem wichtigsten Fall, Präsentieren ohne iPhone – kam nichts an.
- **Entscheidung:** `ScrollWheelTap`: `CGEvent.tapCreate` auf Sitzungsebene, nur `listenOnly` und nur `scrollWheel`, Quelle im Haupt-Run-Loop. Er verändert keine Ereignisse und braucht dieselbe Eingabeüberwachung (ADR-14). Liegt das Fenster unter dem Zeiger in macprompter, wird nur bei `PresentationWindow` gescrollt; das Prompter-Panel behandelt seine Ereignisse selbst, Bibliothek und Einstellungen behalten ihr eigenes Scrollen. Ein vom System deaktivierter Tap wird wieder eingeschaltet. Der Tap entsteht erst mit vorhandener Freigabe und nie im Test-Host.
- **Konsequenzen:** Vom Maintainer am 27.10.2026 mit einer Testversion bestätigt (Präsentation, nicht scrollbare Flächen, andere Apps). Der Tap selbst ist ohne Freigabe nicht automatisch testbar; geprüft werden Fensterregel, Lebenszyklus und Anfrage der Freigabe.

## ADR-17 · Schreibweisen angleichen statt Schwellen senken (27.10.2026)

- **Kontext:** Die Wortausrichtung vergleicht normalisierte Wörter exakt. Apples Erkenner formatiert Zahlen, Abkürzungen und Komposita aber anders als viele Skripte (gemessen: „drei“ statt „3“, „25“ statt „fünfundzwanzig“, „Dr.“ statt „Doktor“, „email“ statt „e-mail“). Beim Streaming steht das neueste Wort am Ende des Teilresultats; passte es nicht, hing die Markierung ein bis drei Wörter hinterher.
- **Entscheidung:** `LexicalBridge` bildet gehörte Wörter vor der Ausrichtung auf die Schreibweise des Skripts ab: Zahlenwerte, Prozentzeichen, Bindestrich-/Kompositumformen, eine feste Tabelle für Abkürzungen und Kurzformen sowie knapp verfehlte lange Wörter nahe der erwarteten Position (nicht während eines Einschubs). Nur Entsprechungen, die im Skript vorkommen; wörtlich vorhandene gehörte Wörter werden nie umgeschrieben. Ausrichtung und Schwellen bleiben unverändert. Standardmäßig aktiv, weil es keine neue Unsicherheit einführt, sondern Formatierungsunterschiede beseitigt; die knapp verfehlten Wörter sind auf das lokale Fenster und eine eindeutige Entsprechung begrenzt.
- **Konsequenzen:** Im Streaming-Benchmark 2 statt 24 Hänger bei 70 gehörten Wörtern, Zuordnungsdauer praktisch unverändert. Kein Modell, keine Abhängigkeit. Die Tabelle deckt nur Deutsch und Englisch ab und muss bei neuen Fällen ergänzt werden. Mit echtem Mikrofon und natürlicher Sprache noch nicht gemessen.

## ADR-18 · `SpeechTranscriber` bleibt, kein Diktiermodell für Skriptvokabular (27.10.2026) – teilweise ersetzt durch ADR-20

- **Kontext:** Eigennamen und Fachbegriffe aus dem Skript (ein ungewöhnlicher Nachname, „macprompter“) erkennt `SpeechTranscriber` oft falsch. Es ignoriert `AnalysisContext.contextualStrings`. `DictationTranscriber` berücksichtigt das Vokabular und erkannte damit alle Namen eines Testsatzes.
- **Entscheidung:** Standard bleibt `SpeechTranscriber` mit `.fastResults`. `DictationTranscriber` war im Echtzeitvergleich pro Ergebnis rund 130–150 ms langsamer (Median 162–185 ms statt 24–37 ms) und ohne Vokabular ungenauer. Das widerspricht „Geschwindigkeit hat Vorrang“. Zwei Module parallel auf demselben Audio würden die Ausrichtung mit doppelter Evidenz belasten und wurden nicht weiter verfolgt.
- **Konsequenzen:** Falsch erkannte Namen bleiben Lücken, die die Ausrichtung überbrückt (ein fehlendes Wort mit zwei aussagekräftigen Nachbarn). Eine spätere, standardmäßig ausgeschaltete Option „Namen und Fachbegriffe aus dem Skript (langsamer)“ ist möglich, falls echte Takes zeigen, dass solche Lücken häufig stören. Messwerte: [SPEECH_LATENCY_RESULTS.md](SPEECH_LATENCY_RESULTS.md).

## ADR-19 · Scrollen im Sprechtempo als begrenzter Vorgriff (28.10.2026)

- **Kontext:** Die messbare Kette (Audioblock, Erkennung, Zuordnung, Markierung) liegt unter 0,1 s. Ein Wort kann aber erst nach seinem Ende erkannt werden; bei 250–400 ms pro Wort liegt die Markierung deshalb immer etwa ein Wort hinter Stimme und Blick. Schnellere Modelle ändern das nicht (ADR-18). Der Maintainer wollte am 28.10.2026 ausdrücklich eine „optimistische“ Anzeige und hat dafür eine Ausnahme vom Grundsatz „Nichts erfinden“ freigegeben.
- **Entscheidung:** Option *Im Sprechtempo scrollen* unter Einstellungen → Lesen → Prompter, nur im Modus Stimme, standardmäßig aus (`ReadingLead`). Zwischen erkannten Wörtern gleitet der Text im Tempo der letzten drei Sekunden weiter, höchstens 24 Zeichen über das zuletzt bestätigte Wort hinaus. Nach 0,9 s ohne bestätigtes Wort oder bei Stille (Pegelschwelle mit sich anpassendem Grundrauschen) bleibt er stehen; er läuft nie von selbst zurück. Die gesprochene Zeile steigt stetig von der zweiten Zeile nach oben, statt einmal pro Zeile zu springen. Markierung, Ausrichtung und Sprungregeln bleiben unverändert; `PlaybackGate` hat weiter Vorrang.
- **Verworfen:** *Nächstes Wort vormerken*. Dabei wurde das nächste Skriptwort blass markiert, sobald man nach einem erkannten Wort weitersprach, und bei fehlender Bestätigung zurückgenommen. Der Maintainer hat es am 28.10.2026 getestet und abgelehnt („gefällt mir gar nicht“); es wurde vollständig entfernt.
- **Konsequenzen:** Bei eingeschalteter Option kann der Text kurz vor der tatsächlichen Stelle stehen, höchstens drei bis vier Wörter. Laute Umgebungen können die Pegelschwelle täuschen; dann gleitet er bis zur Grenze von 0,9 s weiter. Der Maintainer findet die Option „eigentlich ganz cool“; deshalb steht sie unter „Lesen“ statt unter „Experimentell“.

## ADR-20 · Diktiermodell mit Skriptvokabular als Standarderkennung (28.10.2026) – Schalter entfällt mit ADR-22

- **Kontext:** ADR-18 verwarf `DictationTranscriber`, weil seine Ergebnisse rund 140 ms nach dem *Ende des Teilresultats* ankamen, `SpeechTranscriber`-Ergebnisse dagegen nach 24–37 ms. Diese Kennzahl war ungeeignet: Vorläufige Ergebnisse tragen nur einen Zeitbereich für den ganzen Text, nicht pro Wort. Gemessen gegen die Wortzeiten der finalen Ergebnisse liefert `SpeechTranscriber` neue Wörter nur in Schüben etwa alle 0,92–0,95 s; ein Wort erscheint im Median ~0,6 s und bei p95 1,0–1,8 s nach seinem Ende. Eine Option für einen schnelleren Takt gibt es nicht. `DictationTranscriber` liefert alle 0,25–0,28 s und berücksichtigt `contextualStrings`. Im echten Take des Maintainers: Takt 946 → 255 ms, Wort nach seinem Ende im Median 632 → 436 ms, Ereignisse mit Fortschritt 60 → 70 %, „Wort nicht im Skript“ 51 → 31, Einschub 6 → 0; Urteil: „viel schneller und besser“.
- **Entscheidung:** `DictationTranscriber` ist Standard; Einstellungen → Steuerung → Sprachsteuerung schaltet auf `SpeechTranscriber` zurück. Fehlt für eine Sprache das Diktiermodell, wird automatisch `SpeechTranscriber` verwendet. `Recognizer` kapselt beide für App und Integrationstests. Vokabular: `contextualStrings` kosten bei jedem Start ~5,5 ms pro Eintrag (25: 242 ms, 400: 2,4 s, 800: ~4 s). Während der laufenden Erkennung gesetzt, wirken sie nicht auf bereits laufende Sprache. Deshalb werden nur Wörter übergeben, die das Modell sonst nicht kennt: Skriptwörter außerhalb des Wortschatzes von Apples On-Device-Wortmodell (`NLEmbedding.wordEmbedding`, rund 50.000 Wörter) oder mit Ziffern bzw. Großbuchstaben im Wortinneren, längste zuerst, höchstens 50. Die Rechtschreibprüfung von macOS taugt dafür nicht, weil sie Namen und alle vom Nutzer gelernten Wörter akzeptiert.
- **Konsequenzen:** Ohne Vokabular erkennt das Diktiermodell schlechter („Matoma“ statt „macprompter“); mit dem schmalen Vokabular trifft es Namen, im Test sogar besser als mit allen Skriptwörtern. Es schreibt Zahlen teils zerlegt („2 0 26“) und lässt mitunter Wörter aus. Wörter, die erst im finalen Ergebnis auftauchen, zählt die Diagnose getrennt, statt sie in die Latenz zu mischen. Der Grundrückstand von ~0,4–0,5 s pro Wort bleibt; weniger ginge nur mit einem anderen Modell (Streaming auf Laut- bzw. Wortteilebene, eigener Versuch).

## ADR-21 · Kein Fremdmodell für Streaming auf Laut- oder Wortteilebene (28.10.2026)

- **Kontext:** Nach ADR-20 erscheint ein Wort im Median ~0,45 s nach seinem Ende. Weniger ginge nur mit einem Streaming-Modell mit kleinen Blöcken und einer Suche nach den erwarteten Skriptwörtern (z. B. NVIDIA Nemotron Streaming oder ZIPA mit CTC Word Spotting). Der geschätzte Gewinn liegt bei 0,2–0,3 s und ist nicht gemessen. Dafür bräuchte es ein Fremdmodell und vermutlich ein Fremdpaket, eine Core-ML-Umwandlung, 100–600 MB Modellgröße und viel eigene Abstimmung.
- **Entscheidung:** Der Maintainer verzichtet darauf („das will ich nicht angehen“). Die Erkennung bleibt bei Apples Modulen (ADR-20).
- **Konsequenzen:** Keine Fremdmodelle oder -pakete für die Erkennung vorschlagen, solange der Maintainer das nicht selbst anstößt. Weitere Verbesserungen im Rahmen von Apple-Frameworks und der eigenen Wortausrichtung sind weiter möglich.

## ADR-22 · Diktat und semantische Rückkehr immer aktiv, „Experimentell“ wird „Diagnose“ (28.10.2026)

- **Kontext:** Alle echten Takes des Maintainers liefen mit „Umformulierungen erkennen“ (semantische Rückkehr, ADR-4) und zuletzt mit der Diktiererkennung (ADR-20); die guten Messwerte stammen aus genau dieser Kombination. Der Maintainer möchte beides nicht mehr steuern müssen.
- **Entscheidung:** Beide Schalter entfallen. Die Sprachsteuerung nutzt immer `DictationTranscriber` mit seltenen Skriptwörtern als Vokabular; ohne Diktiermodell für die Sprache greift automatisch `SpeechTranscriber`. Die semantische Rückkehr läuft im Modus Stimme immer im Hintergrund, unverändert vorsichtig: nur nach einer fehlgeschlagenen Wortzuordnung, höchstens 24 Wörter voraus, nur mit eindeutigem Skriptwort, Ergebnisse höchstens 250 ms alt. Fehlt das Satzmodell, ist sie inaktiv. Der Einstellungsbereich „Experimentell“ heißt jetzt „Diagnose“: Verfügbarkeit der Satzmodelle und Sprachdiagnose. Neu ist die Zeile „Rückkehr per Satzmodell“, damit sichtbar wird, wie oft die semantische Rückkehr tatsächlich eingreift.
- **Konsequenzen:** Gespeicherte Werte der beiden Schalter in `preferences.v1` werden beim Lesen ignoriert und beim nächsten Speichern entfernt; alle übrigen Einstellungen bleiben erhalten (Test). Liefert das Diktiermodell bei einem Skript schlechte Ergebnisse, gibt es keinen Schalter mehr; `Recognizer` behält beide Wege, ein Schalter wäre schnell wieder eingebaut. Neue unsichere Heuristiken bleiben nach AGENTS.md standardmäßig aus und bekommen einen eigenen Schalter, bis der Maintainer sie erprobt hat.

## ADR-23 · stdio-Helfer mit eigener Sandbox für Claude Desktop und Cowork (01.11.2026)

- **Kontext:** Claude Desktop und Cowork binden lokale MCP-Server nur als Programm über stdio ein; HTTP-Connectors laufen über Anthropics Server und erreichen `127.0.0.1` nicht. Der Server in der App (MCP.md) war für sie nur über ein Fremdpaket wie `mcp-remote` (Node.js) nutzbar.
- **Entscheidung:** Die App bringt das Hilfsprogramm `macprompter-mcp` in `Contents/Helpers` mit. Es reicht stdio-Zeilen an den bestehenden HTTP-Endpunkt weiter, hält keinen Zustand und startet die App bei Bedarf im Hintergrund. Es läuft in einer eigenen Sandbox mit nur `com.apple.security.network.client`, ohne Dateizugriff; der Maintainer hat diese Variante am 01.11.2026 gegenüber einem Helfer ohne Sandbox und einer reinen `mcp-remote`-Anleitung gewählt. Token und Port kommen über Umgebungsvariablen aus der Client-Konfiguration.
- **Konsequenzen:** Die Entitlements der App bleiben unverändert, die ausgelieferte App kann weiterhin keine ausgehenden Verbindungen öffnen; nur der Helfer kann es. `scripts/install.sh` signiert den Helfer vor der App mit seinen eigenen Entitlements neu. Wechselt die Signatur des Helfers (z. B. ad hoc → Zertifikat), fragt macOS einmal, ob er auf seinen bisherigen Container zugreifen darf. Der Container ist leer, die Frage lässt sich gefahrlos bestätigen.

## ADR-24 · Synthetische Testaudios werden lokal erzeugt statt eingecheckt (09.11.2026)

- **Kontext:** Die vier Audiodateien der `SpeechIntegrationTests` stammen aus den macOS-Systemstimmen (`say`, Anna und Samantha). Apples Softwarelizenz erlaubt die Nutzung der Systemstimmen für eigene, nicht kommerzielle Inhalte, aber nicht deren Veröffentlichung oder Weitergabe. Mit dem öffentlichen Repository wären die Dateien veröffentlicht.
- **Entscheidung:** `scripts/make_fixtures.sh` erzeugt die Dateien bei Bedarf aus festen Texten mit `say`; `scripts/check.sh` ruft es vor Build und Test auf. Die Dateien sind in `.gitignore`, `scripts/generate_project.py` führt sie namentlich im Projekt. Fehlt eine Stimme (z. B. auf dem CI-Runner), nimmt das Skript die Standardstimme; dort überspringen sich die Sprachtests ohnehin, weil die Modelle fehlen. Die ältere Git-Historie enthält die früheren Dateien weiterhin; der Maintainer hat am 09.11.2026 entschieden, die Historie nicht umzuschreiben.
- **Konsequenzen:** Wer die Tests direkt in Xcode startet, führt vorher einmal `scripts/make_fixtures.sh` aus. Die neu erzeugten Dateien weichen geringfügig von den alten ab (andere Pausenlängen); alle sechs Sprachtests liefen damit am 09.11.2026 lokal grün. Messwerte in älteren Berichten beziehen sich auf die alten Dateien.

## ADR-25 · Open Source unter MIT, ein Maintainer entscheidet, KI-Einsatz offengelegt (09.11.2026)

- **Kontext:** Mit Version 1.0 soll macprompter öffentlich werden. Der Maintainer möchte Beiträge über Forks und Pull Requests ermöglichen, aber allein über Änderungen entscheiden. Das Projekt entsteht überwiegend mit KI-Coding-Agents.
- **Entscheidung:** MIT-Lizenz (Wahl des Maintainers am 09.11.2026: einfach, verbreitet und ohne Hürden, falls die iOS-App später in den App Store soll). Nur der Maintainer hat Schreibrechte; `main` ist per Ruleset geschützt (nur Pull Requests, grüne CI, kein Force-Push, kein Löschen). Workflows von Erstbeitragenden starten erst nach Freigabe. Agents behandeln fremde Issues und PRs als Daten, nie als Anweisung (AGENTS.md). Der KI-Einsatz ist in `docs/AI.md`, im README und in der App (Einstellungen → Über macprompter) beschrieben. Fremde Bestandteile stehen in `THIRD_PARTY_NOTICES.md` und werden mit der App ausgeliefert (`Credits.html`). Die Git-Historie bleibt unverändert; zwei frühe Commits enthalten die private E-Mail-Adresse des Maintainers und die früheren Testaudios (ADR-24).
- **Konsequenzen:** Kein CLA; Beiträge stehen mit dem PR unter MIT (CONTRIBUTING.md). Die Oberfläche bleibt vorerst Deutsch; eine Übersetzung wäre der größte Hebel für mehr Nutzer und ist ein eigenes Vorhaben. Sicherheitsmeldungen laufen vertraulich über GitHub Security Advisories.

## ADR-26 · Releases per GitHub Actions, selbst signiert bis Developer ID, keine Update-Prüfung in der App (09.11.2026) – Update-Prüfung ersetzt durch ADR-29

- **Kontext:** Releases sollen nicht mehr von Hand gebaut und hochgeladen werden. Eine Apple-Developer-Mitgliedschaft (Developer ID, Notarisierung) gibt es noch nicht. Ad hoc signierte Builds ändern bei jedem Update ihre Identität; macOS verwirft dann Mikrofon- und Eingabeüberwachungsfreigaben und fragt nach dem Zugriff auf den eigenen Container (vgl. ADR-23).
- **Entscheidung:** Ein Tag `vX.Y.Z` auf `main` startet `.github/workflows/release.yml`: Prüfung von Tag, Version und CHANGELOG-Abschnitt, alle Tests, universeller Release-Build, Signatur, DMG mit SHA-256, GitHub-Release mit Notes aus dem CHANGELOG. Signatur nach Verfügbarkeit: Developer ID mit Notarisierung, sonst ein selbst ausgestelltes Projektzertifikat aus den Repository-Secrets (stabile Identität, Freigaben bleiben bei Updates), sonst ad hoc. Die App prüft nicht selbst auf Updates: Das bräuchte Netzwerkzugriff oder Sparkle und widerspricht ADR-1; stattdessen führt Hilfe → Versionshinweise zur Release-Seite. Die iOS-App wird nicht verteilt, nur als Quellcode.
- **Konsequenzen:** Bis zur Notarisierung müssen Nutzer den ersten Start über „Dennoch öffnen“ bestätigen; README und Release-Notes erklären das. Der Build ist universell, getestet wird nur auf Apple Silicon. Das Zertifikat liegt nur als Secret; geht es verloren, fragt macOS nach dem nächsten Update einmal neu nach den Freigaben. Release-Notes sind Pflicht und werden vom Workflow geprüft (docs/RELEASING.md).

## ADR-27 · Neutrale App-Kennung `io.github.fng-2002.macprompter` (09.11.2026)

- **Kontext:** Bundle-IDs, Dateityp und Schlüsselbund-Dienst enthielten den Vornamen des Maintainers. Er möchte im öffentlichen Projekt nur unter seinem GitHub-Namen FNG-2002 erscheinen.
- **Entscheidung:** Alle Kennungen beginnen mit `io.github.fng-2002.macprompter` (App, `.mcp`, `.tests`, `.remote`, Dateityp `.script`, Schlüsselbund `.remote.pairings`). Copyright und Texte nennen nur FNG-2002. Ausdrückliche, einmalige Ausnahme zu „Nutzerdaten sind heilig“, vom Maintainer am 09.11.2026 freigegeben: Es gab noch keine öffentliche Version, und seine eigene Bibliothek wurde von Hand in den neuen Container übernommen. Der neue Start erfolgt in einem neuen Repository mit einem einzigen Commit; das bisherige liegt privat als `macprompter-archive`.
- **Konsequenzen:** Ab 1.0.0 ist die Kennung fest. Eine spätere Änderung würde wieder alle Daten, Freigaben und Dateizuordnungen trennen und ist ausgeschlossen.

## ADR-28 · Eine Signatur für lokale Testversionen und Releases (09.11.2026)

- **Kontext:** Lokale Testversionen waren mit „Apple Development“ signiert, Releases mit dem Projektzertifikat (ADR-26). Beide installieren sich als dieselbe App nach `/Applications`, aber bei jedem Wechsel fragte macOS neu nach Mikrofon, Eingabeüberwachung und Containerzugriff. Der Maintainer möchte nur eine App haben.
- **Entscheidung:** `scripts/make_signing_identity.sh` legt das Projektzertifikat zusätzlich im Anmelde-Schlüsselbund ab und markiert es dort für die Code-Signatur als vertrauenswürdig; `scripts/install.sh` nutzt es bevorzugt. Dafür wurde das Zertifikat am 09.11.2026, kurz nach dem Release 1.0.0, einmalig neu ausgestellt (vorher existierte es nur als Secret). Keine zweite App mit eigener Kennung für Tests.
- **Konsequenzen:** Testversionen arbeiten mit der echten Bibliothek; vor riskanten Änderungen an Datenformaten sichert der Agent die Skripte vorher als `.macprompter`-Dateien. Nutzer von 1.0.0 bestätigen die Freigaben beim nächsten Update einmal. Liegt das Zertifikat nicht im Schlüsselbund (andere Rechner, Mitwirkende), signiert `install.sh` wie bisher mit „Apple Development“ oder ad hoc.

## ADR-29 · Update-Suche über die GitHub-API als Ausnahme vom Netzwerkverzicht (10.11.2026)

- **Kontext:** Ohne Update-Prüfung (ADR-26) erfahren Nutzer nur über GitHub von neuen Versionen. macOS bietet außerhalb des App Stores keine eingebaute Update-Funktion; vollständige Auto-Updates gäbe es nur mit Sparkle (Fremdpaket, in der Sandbox aufwendig, am besten mit Developer ID). Der Maintainer hat am 10.11.2026 eine schlanke Update-Suche freigegeben, standardmäßig an.
- **Entscheidung:** `UpdateChecker` fragt etwa 5 s nach dem Start und danach alle 24 Stunden `https://api.github.com/repos/FNG-2002/macprompter/releases/latest` ab (flüchtige `URLSession`, keine Cookies, kein Cache, User-Agent nur „macprompter“). `UpdateCheck` vergleicht die Versionsnummer numerisch und ignoriert Entwürfe, Vorabversionen und Links außerhalb von github.com. Eine neuere Version zeigt einen Hinweis in der Bibliothek (pro Version ausblendbar); Hilfe → „Nach Updates suchen …“ und Einstellungen → Über macprompter prüfen von Hand. Installiert wird nichts. Dafür bekommt die Release-App `com.apple.security.network.client`. Der Testhost fragt GitHub nie an.
- **Konsequenzen:** Erste Verbindung der App ins Internet außer Apples Modell-Download; GitHub sieht die IP-Adresse. README, Einstellungen → Privatsphäre und AGENTS.md sagen das. Mit Developer ID und Notarisierung kann später Sparkle für echte Auto-Updates folgen; das wäre eine neue Entscheidung (Fremdpaket).

## ADR-30 · Alle lokalen Diktiersprachen, keine Server-Erkennung (10.11.2026)

- **Kontext:** Der Maintainer hat am 09.11.2026 die App textream (MIT) ausprobiert und fand deren Erkennung in mehreren Sprachen gut. Analyse des Quellcodes: textream nutzt `SFSpeechRecognizer` mit `contextualStrings`, verlangt aber nicht `requiresOnDeviceRecognition` und hat Netzwerkzugriff; Apple darf dann auf Servern erkennen. Das Weiterlaufen bei freier Rede, das dem Maintainer negativ auffiel, kommt von der großzügigen Zuordnung (Wortanfänge reichen, kleine Sprünge nach vorn immer erlaubt). Code wurde nicht übernommen.
- **Entscheidung:** Keine Server-Erkennung (ADR-1). Stattdessen alle Sprachen von `DictationTranscriber.supportedLocales` (54 Varianten auf macOS 26), ohne Schriften ohne Leerzeichen zwischen Wörtern (Japanisch, Chinesisch, Kantonesisch, Thai), weil die Wortausrichtung auf Wörtern arbeitet. `SpeechLanguage` ist jetzt ein Struct mit BCP-47-Kennung und wird weiter als Zeichenkette gespeichert, sodass `scripts.json` aus 1.0 unverändert lesbar bleibt. `SpeechLanguage.suggestion` schlägt per `NLLanguageRecognizer` (mindestens 40 Buchstaben, Konfidenz ≥ 0,8) die Sprache des Skripts vor; umgestellt wird nur per Klick. Die semantische Rückkehr bleibt auf Deutsch und Englisch, weil ihre Schwellen nur dafür gemessen sind. Der Wort-Tokenizer nimmt kombinierende Zeichen (`\p{M}`) ins Wort auf (Hindi, zerlegte Umlaute). Die Zuordnung bleibt streng.
- **Konsequenzen:** Weitere Sprachen sind nur mit synthetischen Tests auf Deutsch und Englisch geprüft; Zahlwörter gleicht `LexicalBridge` weiterhin nur für Deutsch und Englisch an. Andere Sprachen nutzen die gleiche Ausrichtung ohne Satzmodell.

## ADR-31 · Vorgezogene Wortmarkierung im Sprechtempo (10.11.2026)

- **Kontext:** Ein Wort wird erst etwa 0,45 s nach seinem Ende erkannt (ADR-20); die Markierung liegt deshalb rund ein Wort hinter der Stimme. Der Maintainer wollte am 10.11.2026, dass sie auf dem gerade gesprochenen Wort liegt, und hat dafür eine weitere Ausnahme vom Grundsatz „Nichts erfinden“ freigegeben. Das am 28.10.2026 abgelehnte „Nächste Wort vormerken“ (blasse Zweitmarkierung, die zurückgenommen wurde, ADR-19) sollte sich nicht wiederholen.
- **Entscheidung:** Option *Markierung im Sprechtempo vorziehen* unter Einstellungen → Lesen, nur im Modus Stimme. Nach einem Experiment und dem Test des Maintainers in echten Takes („sehr viel besser“) standardmäßig an. `ReadingLead.advanceSpoken` schätzt die Sprechposition aus dem Tempo der bestätigten Wörter plus der Erkennungsverzögerung von 0,45 s; die normale Markierung springt auf das Wort, in das diese Position hineinreicht, höchstens zwei Wörter über das zuletzt erkannte hinaus. Sie bewegt sich nur bei Stimmaktivität, höchstens 0,9 s nach dem letzten bestätigten Wort und nicht abseits des Skripts; eine später eintreffende Erkennung eines früheren Worts zieht sie nicht zurück, nur ein Wiedereinstieg setzt sie neu. Ausrichtung, Sprungregeln und `PlaybackGate` bleiben unverändert.
- **Konsequenzen:** Die Markierung kann bis zu zwei Wörter vor der tatsächlichen Stelle stehen, etwa wenn der Sprecher mitten im Satz abbricht. Bei frischem Tempo nach einer Pause über 1,5 s läuft sie erst nach einigen erkannten Wörtern wieder vor.

