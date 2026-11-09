# Abnahme und bekannte Grenzen

## Lokale Rückkehrprüfung am 24.09.2026

- 76 Tests geprüft: vollständiger Lauf mit 74 Tests erfolgreich, anschließend die erweiterte Rückkehrsuite mit 16 Tests inklusive zwei zusätzlicher Grenzfälle erfolgreich; keine übersprungenen Tests.
- Neue Szenarien: veränderter DE/EN-Satzanfang, kurze Ersetzungen/Auslassungen zwischen Schlüsselwörtern, nachgeschobene Wörter, Segmentwechsel, korrigierte Treffer, Hover, vertauschte/mehrdeutige/vereinzelte Treffer und größere Lücken. Die vier bestehenden lokalen Sprachintegrationstests bestanden unverändert.
- Fünf zuvor steckenbleibende Transkriptfälle wurden im direkten Vorher-/Nachher-Vergleich jeweils 30-mal geprüft. Zuvor 0/150 Anschlüsse, danach 150/150. Das sind gezielte synthetische Szenarien und keine Schätzung der Erfolgsrate bei freien Takes.
- Zuordnungszeit dieser Fälle im optimierten Build: p95 0,228 ms (vorher 0,218 ms). Langes Skript weiterhin rund 3,27 ms p95. Kein gemessener relevanter zusätzlicher Verarbeitungsrückstand; unverändert keine Ende-zu-Ende-Latenzgarantie.
- Release-Build und Signatur geprüft. Keine neuen Modelle oder Netzwerkdienste.

## Erste Sprachoptimierung am 24.09.2026

- 60 XCTest-Tests erfolgreich, keine übersprungenen Tests. Zusätzliche Fälle für sofortigen lokalen Anschluss nach Einschüben, DE/EN-Füllwörter, Korrekturen, zufällige Treffer in Anekdoten, Rücksprünge trotz kollidierendem Anschlusswort und sofortige Wortmarkierung ohne Warteschlange.
- Vier lokale SpeechAnalyzer-Integrationstests. Zwei führen synthetisches Audio zeitgetreu zu und prüfen Pause, freien Einschub und Wiedereinstieg vor dem Ende der Aufnahme.
- Optimierter Zuordnungsbenchmark mit 2.200 Skriptwörtern: 0,17 ms Median, 3,14 ms p95, 5,46 ms Maximum. Keine Ende-zu-Ende-Latenzgarantie; Details und reproduzierbare Messung in [SPEECH_LATENCY_RESULTS.md](SPEECH_LATENCY_RESULTS.md).
- Keine neuen externen Modelle, Cloud-Dienste oder Aufnahmeberechtigungen. Diagnose umfasst maximal 256 Zeitmesspunkte im Arbeitsspeicher, ohne Audio/Transkript.

## Frühere Abnahme am 23.09.2026

- macOS 27.0 (26A428), Apple Silicon, Xcode 26.2.
- 39 XCTest-Tests erfolgreich, ohne übersprungene Tests: Parser, Wortausrichtung, Hover, Persistenz, Reader-Scrollposition, OpenDyslexic, Cue-Styling, Audiokonvertierung und DE-/EN-Sprachintegration.
- Beide Sprachintegrationstests verwenden synthetisches Testaudio und laufen in der sandboxed App durch denselben Audio-Konverter und SpeechAnalyzer-Stream wie der Mikrofonbetrieb. Deutsch und Englisch wurden tatsächlich transkribiert; keine Mikrofonfreigabe nötig.
- Skriptstudio und native Einstellungen per UI geöffnet und visuell geprüft. Overlay zusätzlich direkt aus der echten SwiftUI-/AppKit-Ansicht gerendert und auf lesbaren Text und abgesetzte Cues geprüft.
- Fehlerkorrektur: Der Mikrofon-Callback wird explizit außerhalb des MainActor erstellt. Der neue Regressionstest ruft genau diesen Callback auf einer Hintergrundqueue auf und prüft Audioausgabe und Pegelrückmeldung.
- Den optimierten Build mit echtem Mikrofon über „Stimme → Take starten“ gestartet: Status „Hört zu · Deutsch · lokal“ erreicht, anschließend erfolgreich pausiert. Dabei wurde kein Audio gespeichert. Längere gesprochene Live-Skripte bleiben ein manueller Praxistest.
- Rechte Konfigurationsleiste auf 360 pt verbreitert, Hilfstexte gekürzt, Abstände vergrößert und Vorschau an die verfügbare Breite angepasst. Visuell im laufenden Build geprüft.
- Noch nicht praktisch geprüft: längere Live-Skripte, mehrere physische Displays, Drag über Displaygrenzen, fremde Aufnahme-/Meeting-Apps, notarisiertes Distributionspaket.

## Automatisiert

Zusätzliche Szenarien für die Sprachführung: längere Anekdoten, Rückkehr in frühere und entfernte Passagen, Wort-für-Wort-Wiedereinstieg, kurze Schlussphrasen, mehrdeutige Wiederholungen, Füllwörter, Erkennungsfehler, doppelte/korrigierte Teilresultate und zufällige Einzelwörter mit altem Kontext. Reader-/Session-Tests prüfen dezente Wortmarkierung, Nachziehen über Cue-Abstände während Stille, sofortige Hover-Sperre und zeitunabhängiges Scrollen ohne Überschwingen.

Die XCTest-Suite prüft Skriptparser, Wortausrichtung, Hover-/Countdown-Sperren, Persistenz und Schutz beschädigter Dateien. Ein erfolgreicher Build allein bestätigt keine funktionierende Spracherkennung oder Unsichtbarkeit in fremden Aufnahme-Apps.

## Auf einem echten Mac prüfen

- **Release-DMG:** DMG von der Release-Seite laden, Prüfsumme vergleichen, nach „Programme“ ziehen, ersten Start über „Dennoch öffnen“ bestätigen. Mikrofon und Eingabeüberwachung freigeben, danach die nächste Version darüber installieren: Freigaben und Skripte müssen erhalten bleiben, ohne Frage nach dem Containerzugriff.
- **Sprache DE/EN:** Modus Stimme wählen, passende Skriptsprache setzen, Mikrofon freigeben und gegebenenfalls Modell laden lassen. Langsam/schnell lesen, schweigen, Wörter auslassen, mit Tastatur zurückgehen. Bei Stille nur noch sanftes Nachziehen bis zur bereits erkannten Zielzeile; danach Stillstand. Bei verweigerter Berechtigung verständliche Fehlermeldung; automatischer Modus bleibt nutzbar.
- **Hover:** In allen drei Modi Maus über das Overlay bewegen. Text, Tastennavigation und Countdown müssen stehen bleiben; nur das Scrollrad bewegt den Text (seit 27.10.2026). Nach Verlassen kein Nachholen während Hover gesprochener Wörter. Explizite Pause darf nicht automatisch enden.
- **Lebenszyklus:** Mikrofon während laufender Erkennung wechseln/abziehen; Hinweis statt Absturz. Ausblenden, Pausieren und Ruhezustand beenden den Audioeingang. Start während Modell-Download abbrechen; keine spätere Geisteraufnahme.
- **Bildschirme:** Notch-MacBook, externes Display, Displays links/rechts/oberhalb, Spaces und Vollbild testen. Frei schwebendes Overlay verschieben. Display abziehen; Overlay muss erreichbar bleiben. Größe und Position nach Neustart prüfen.
- **Aufnahme:** QuickTime / Screenshot-Toolbar, OBS Display Capture, Zoom, Teams, Google Meet jeweils mit Bildschirm- und Fensterfreigabe aufnehmen und die resultierende Datei bzw. Empfängersicht ansehen. Ausschluss kann variieren; keine universelle Garantie.
- **Editor:** Import von TXT, UTF-8-Markdown und RTF; Texte mit Umlauten/Emoji/Cues; Undo/Redo; leeres Dokument; sehr langes Skript; App schließen und erneut öffnen.
- **Lesbarkeit:** Alle drei Schriften, Größen, Zeilenabstände, Spiegelung und Fokuszeile kontrollieren. VoiceOver-Beschriftungen und Tastaturnavigation prüfen.

## Noch nicht enthalten

Automatische Sprachumschaltung innerhalb eines Skripts, Sprechererkennung, individuell belegbare globale Hotkeys, PDF-/DOCX-Import, Fernsteuerung über iPhone und signierte/notarisierte Veröffentlichungen. Die Oberfläche ist derzeit deutsch; englische Skripte und Erkennung sind unterstützt.

## Experimentelle Modellhilfe · 24.09.2026

- 89 automatisierte Tests bestanden, einschließlich DE-/EN-Systemmodellen und lokaler Sprachintegration.
- Release-Build und strikte Signaturprüfung erfolgreich.
- Einstellungen → Experimentell visuell geprüft: Schalter standardmäßig aus; Deutsch und Englisch auf diesem Mac „Lokal verfügbar“; Beschreibung und lokale Verarbeitung sichtbar.
- Modell-Benchmark und Grenzen: [SEMANTIC_RECOVERY.md](SEMANTIC_RECOVERY.md).
- Noch durch natürliche Takes zu vergleichen: kleinere freie Umformulierungen mit aktiviertem/deaktiviertem Schalter, unerwünschte Sprünge bei thematisch ähnlichen Einschüben und Energieverbrauch über längere Zeit. Synthetische Fixtures ersetzen diesen Vergleich nicht.

## Wiedereinstieg und Transkriptduplikate · 05.10.2026

- 98 Tests bestanden, keine übersprungen; einschließlich vollständiger DE-/EN-Sitzungsfälle nach Einschüben, lokaler Sprachintegration und Schutz vor überholten Antworten.
- Identische Teil-/Endresultate erhalten laufende und wartende Modellanfragen; Korrekturen, neue Audioabschnitte und die 250-ms-Grenze bleiben wirksam.
- Optimierter Vorher-/Nachher-Vergleich für die kurze Endprüfung dokumentiert in [SEMANTIC_RECOVERY.md](SEMANTIC_RECOVERY.md).
- Release-Build und strikte Signaturprüfung erfolgreich; App neu gestartet, bestehende Skripte und Einstellungen sichtbar. Kein Mikrofontake gestartet.
- Der Vergleich mit natürlich gesprochenen Einschüben im Alltag steht weiterhin aus.

## Scrollen und Layoutarbeit · 05.10.2026

- 105 Tests bestanden, nichts übersprungen. Enthalten sind ein realer Display-Link mit Start/Hover/Wiederaufnahme, unabhängige Wortmarkierung, Reader-Erhalt bei Größen-/Dockwechseln sowie alle bisherigen lokalen Sprachtests.
- Release-Build und strikte Signaturprüfung erfolgreich.
- App neu gestartet, zuvor ausgewähltes englisches Skript wieder ausgewählt. Vorschau geöffnet und wieder ausgeblendet; App bereit, Mikrofon aus.
- Kandidatensuche und Scrollkurve getrennt gemessen: [RENDERING_OPTIMIZATION.md](RENDERING_OPTIMIZATION.md).
- Energieverbrauch unter längerer Konferenzlast und visuelle Gleichmäßigkeit auf mehreren Bildschirmen bleiben manuell zu prüfen; aus dem Mikrobenchmark wird keine Akkulaufzeit oder Gesamt-Sprachlatenz abgeleitet.

## Agent-Setup und Toolchain · 25.10.2026

- 106 Tests bestanden mit Xcode 27.1 auf macOS 27.0 (Apple Silicon), keine übersprungen, keine Compiler-Warnungen im App-Code.
- Erster CI-Lauf auf GitHub `macos-26` (Xcode 26.6). Dort ist systemweit „Bewegung reduzieren“ aktiv; ein Scrolltest hing von dieser Systemeinstellung ab. Die Systemabfrage ist jetzt in der Sitzung injizierbar, ein zusätzlicher Test prüft das direkte Springen bei reduzierter Bewegung.
- `scripts/check.sh --release`: Debug-Tests, Release-Build und strikte Signaturprüfung erfolgreich. Der Projektgenerator erzeugt ein unverändertes `project.pbxproj`.
- Keine Änderung am App-Code; nur Prüfskript, CI und Dokumentation. Manuelle Prüfungen aus früheren Abschnitten bleiben unverändert offen.

## PDF-Präsentationen · 26.10.2026

- 128 Tests bestanden mit Xcode 27.1 auf macOS 27.0 (Apple Silicon), keine Compiler-Warnungen. Neu sind 22 Tests: abgeleiteter Skripttext und Folien-Timeline, Gruppen mit `[Weiter]` bzw. gleichmäßiger Verteilung, Zuordnung nach PDF-Updates (eingefügt, entfernt, verschoben, bearbeitet, Bildseiten, identische Seiten, Einfügen in Gruppe), Abwärtskompatibilität von `scripts.json` und `preferences.v1`, Foliensynchronisation in Stimme und Automatik, Hover-Vorrang, Sprung des echten Readers sowie Import und Update echter, im Test erzeugter PDFs.
- Folien-Editor, Referentenansicht und Folienfenster aus den echten SwiftUI-Views mit einer generierten PDF gerendert und angesehen. Dabei behoben: Seiten ohne eigenen Hintergrund wurden schwarz statt papierweiß gezeichnet.
- Debug-App gestartet; die bestehende Bibliothek wurde unverändert geladen (Struktur geprüft, keine neuen Felder in Skripten ohne PDF). Screenshots der laufenden App waren ohne Bildschirmaufnahme-Freigabe nicht möglich.
- Damit ist der PDF-Teil von „Noch nicht enthalten“ (oben) umgesetzt; DOCX-Import fehlt weiterhin.
- **Manuell offen:** PDF über den Dateidialog importieren und verknüpfen. Echte Keynote-/PowerPoint-Exporte mit eingefügten, gelöschten und verschobenen Folien neu exportieren und die Zuordnung prüfen (Bookmark-Erkennung beim Aktivieren der App). Präsentationsmodus mit einem und mit zwei physischen Bildschirmen inklusive Referentenansicht, Ausblenden von Dock und Menüleiste, Abziehen des Projektors während der Präsentation. Presenter-Fernbedienungen (Bild↑/↓, B). Sprachmodus über mehrere Folien mit echtem Mikrofon. ⌥⌘←/→ während der Präsentation aus einer anderen App heraus.

## iPhone-Fernbedienung · 26.10.2026

- 148 Tests bestanden mit Xcode 27.1 auf macOS 27.0 (Apple Silicon), keine Compiler-Warnungen in Mac- und iOS-Target. Neu sind 20 Tests: Framing bei beliebiger Stückelung und Größenlimit, übersprungene unbekannte Nachrichten, Scroll-Bündelung, Codeformat, PBKDF2-, HMAC- und X25519-Ableitung, Kopplungsfenster (Frist, 5 Fehlversuche), Befehle über die `PlaybackGate` (Hover blockiert Scrollen und Foliensprung des Texts), Tempo-/Modusgrenzen, Skriptwechsel, Folien über die Session, keine Skripttexte im kodierten Status, abwärtskompatible `preferences.v1`, nie überschriebene unlesbare Geräteliste, gerenderter Einstellungsbereich und ein vollständiger TLS-PSK-Loopback-Durchlauf zwischen echtem `RemoteServer` und dem iOS-Client (falscher Code wird gezählt, Kopplung, Befehle, Status, geschlossenes Fenster, Widerruf auf TLS-Ebene).
- `scripts/check.sh --release`: Release-Build und strikte Signaturprüfung des Mac, iOS-Release-Build für Geräte ohne Signatur.
- Messung TLS-Version (Versuchsprogramm, siehe [REMOTE.md](REMOTE.md)): Network.framework handelt mit PSK nur TLS 1.2 / 0x00A8 aus; mehrere PSK-Identitäten pro Listener funktionieren, angenommene Verbindungen überleben einen Listener-Neustart.
- **Echter Ende-zu-Ende-Lauf auf diesem Mac:** Mac-App (Debug-Code, aber mit den Release-Entitlements, also ohne `network.client`) mit `-RemoteDebugPairing YES` gestartet; `dns-sd` zeigte den Dienst mit TXT `v`, `id`, `pair`, `salt`. iOS-Simulator (iPhone 17 Pro, iOS 26.2) mit `-RemoteDebugPairCode` gestartet: Er fand den Mac per Bonjour, koppelte sich, verband sich mit dem neuen Geräteschlüssel und zeigte den echten Status (Skripttitel, Modus Stimme, „Prompter ausgeblendet“, Scroll-Sperrhinweis). Nach Neustart der iOS-App verband sie sich automatisch wieder (Schlüsselbund). Nach Beenden der Mac-App erschien der Mac unter „Gekoppelt, gerade nicht erreichbar“. Befehle konnten im Simulator nicht angetippt werden; sie sind nur im Loopback-Test automatisiert geprüft. Die dabei angelegte `remote-devices.json` wurde danach wieder entfernt.
- Screenshots angesehen und verbessert: Steueransicht hell/dunkel (Beschriftungen der Transporttasten auf eine Linie gebracht, dunkle Akzentfarbe für ausreichenden Kontrast abgedunkelt), Layout „Nur Folien“ ohne Präsentation (ausgegraut mit Hinweis), Mac-Liste ohne erreichbaren Mac. Mac-Einstellungsbereich aus der echten SwiftUI-View gerendert (Code, Restzeit, Versuche, Geräteliste).
- Damit ist die iPhone-Fernsteuerung aus „Noch nicht enthalten“ (oben) umgesetzt.
- **Manuell offen:** echtes iPhone (Signatur mit eigenem Team), Abfrage „Lokales Netzwerk“ auf iOS und ggf. macOS inkl. Ablehnen, Verbindung ohne gemeinsames WLAN (AWDL/Peer-to-Peer) und Reichweite, Wechsel zwischen WLANs und Ruhezustand des Mac während einer Verbindung, Bedienung aller Tasten, Wischfläche und Schieberegler am Gerät (Haptik, Latenz), VoiceOver und große Schriftgrade auf dem iPhone, Foliensteuerung mit echter PDF-Präsentation inklusive Präsentationsmodus, mehrere gekoppelte iPhones gleichzeitig.

## Deckkraft des Prompters · 26.10.2026

- 150 Tests bestanden (Xcode 27.1, macOS 27.0). Neu: Abwärtskompatibilität und Begrenzung der Deckkraft (20–100 %), gerenderter Overlay-Hintergrund mit 40 % Deckkraft.
- **Manuell offen:** Lesbarkeit des Textes über hellen Folien und Videos bei niedriger Deckkraft; Darstellung an der Notch.

## iOS: Vollbild-Scrollfläche · 26.10.2026

- 151 Tests bestanden, iOS-App baut (Xcode 27.1). Neu: Sperrhinweis der Scrollfläche folgt der Bewegungssperre (Sichtbarkeit, Hover, Countdown). Scroll-Logik und Befehle sind unverändert und weiter durch die bestehenden Akkumulator- und Loopback-Tests abgedeckt.
- **Manuell offen:** Vollbild auf dem iPhone öffnen und schließen, Wischen und Schritt-Tasten mit Sprachsteuerung am Mac, Bildschirm bleibt an, automatisches Schließen beim Verbindungsverlust, VoiceOver und große Schrift.

## Prompter-Größe per Ziehen · 26.10.2026

- 154 Tests bestanden (Xcode 27.1, macOS 27.0). Neu: Größenänderung angedockt (symmetrisch, nach unten) und frei schwebend (gegenüberliegende Kanten bleiben), Grenzen und Erhalt größerer Werte nach Neustart.
- **Manuell offen:** Ziehen an allen Griffen mit echter Maus bzw. Trackpad, Mauszeiger an den Kanten, Verhalten an der Notch und auf großen externen Bildschirmen, Zusammenspiel mit Hover-Pause.

## Vorlagen und Folien mit Schritten · 26.10.2026

- 160 Tests bestanden (Xcode 27.1, macOS 27.0), iOS-App baut. Neu: leere neue Bibliothek, Vorlagenumfang, Aufbau der Beispielpräsentation aus der gebündelten PDF (10 Folien, 12 PDF-Seiten, Schritte über `[Weiter]`), Folien-/Schrittanzeige, Neuableitung gespeicherter Präsentationen beim Laden, Rückfall der iPhone-Anzeige, gerenderte Galerie und Editor.
- Beispiel-PDF sowie Galerie und Editor als Bilder gerendert und angesehen. Korrigiert: Das Diagramm ragte in den Titel, noch verdeckte Punkte waren angedeutet.
- **Manuell offen:** Galerie in der laufenden App, Übernahme aller drei Vorlagen, Präsentationsmodus mit der Beispiel-PDF inklusive Schritten auf Folie 3, Anzeige „Schritt x/y“ auf dem iPhone, erster Start mit leerer Bibliothek.

## Zugang für KI-Agenten (MCP) · 26.10.2026

- 170 Tests bestanden (Xcode 27.1, macOS 27.0), iOS-App baut. Neu: HTTP-Parser (Teilstücke, Chunked, Größen), Zugriffsschutz (Token, Origin, Host, Methode, Pfad), Versionsaushandlung, Werkzeugliste ohne Löschen, alle Werkzeuge mit echter Bibliothek und generierten PDFs inklusive Schritten und neuer PDF-Version, Ordnergrenzen für `pdf_path`, Token-Ablage (0600, unlesbare Datei bleibt unverändert), Loopback-Aufruf über `URLSession`, gerenderte Einstellungsseite.
- Ende-zu-Ende mit der laufenden Debug-App (`-MCPDebugPort`): nur auf 127.0.0.1 erreichbar, über die LAN-Adresse nicht. `curl` prüfte initialize, tools/list, list_scripts, 401 ohne Token und 405 für GET. Claude Code rief `list_scripts` als echter MCP-Client erfolgreich auf. Nur lesend; die echte Bibliothek wurde nicht verändert. Dabei legte die App ihre `mcp.json` (Token) im Container an.
- **Manuell offen:** Einrichtung über die Einstellungsseite in der laufenden App (Schalter, Port ändern, Token kopieren und neu erzeugen, Ordner wählen); eine Präsentation per Agent aus einer PDF im freigegebenen Ordner anlegen und im Editor ansehen; Claude Desktop über `mcp-remote`.

## Korrektur: Prompter-Größe ziehen · 26.10.2026

- Rückmeldung: Ziehen an den Kanten funktionierte nicht. Ursache per Hit-Test im echten Panel ermittelt: Die Griffe meldeten `mouseDownCanMoveWindow = true`, frei schwebend wurde daher das Fenster verschoben. Da das Panel nie Key-Fenster wird, waren Cursor-Rects inaktiv; ohne Größen-Cursor waren die 6 pt schmalen, unsichtbaren Streifen kaum zu finden.
- Behoben: Griffe verschieben das Fenster nicht mehr, ein immer aktiver Tracking-Bereich setzt den Cursor, die Streifen sind 10 pt breit, unten in der Mitte gibt es einen sichtbaren Ziehgriff.
- 171 Tests bestanden. Neu: Drag-Test im echten `PrompterPanel` mit simulierten Mausereignissen, angedockt und frei schwebend; die Größe ändert sich, das Panel bleibt stehen.
- **Manuell offen:** Ziehen mit echter Maus bzw. Trackpad, Cursorwechsel an den Kanten.

## Korrektur: Größe ziehen und Hover-Pause · 26.10.2026

- Rückmeldung: Ziehen klappt nicht zuverlässig, Verdacht Hover-Pause. Ursachen:
  - Das Panel wurde asynchron über die Einstellungsbeobachtung repositioniert und wanderte dabei (angedockt nach unten und zu beiden Seiten). Die Mausposition wurde aber relativ zum Fenster umgerechnet, dadurch entstanden Sprünge.
  - Jedes Repositionieren und SwiftUI-`onHover` setzten die Hover-Pause neu; beim Herausziehen endete sie kurz, und der Text lief weiter.
- Behoben: Während des Ziehens bleibt die Hover-Pause fest, das Panel wird synchron repositioniert, und der Drag nutzt die globale Mausposition. Nach dem Loslassen wird Hover anhand der echten Mausposition neu bestimmt.
- 171 Tests bestanden; der Drag-Test im echten Panel prüft zusätzlich die gehaltene Hover-Pause.
- **Manuell offen:** Ziehen mit echter Maus bzw. Trackpad, langsam und schnell, angedockt und frei schwebend, auch über den Panelrand hinaus.

## macprompter-Dateien und Einstellungen pro Skript · 26.10.2026

- 179 Tests bestanden (Xcode 27.1, macOS 27.0), iOS-App baut; `scripts/check.sh --release` erfolgreich (Info.plist mit Dateityp). Neu: Zuordnung Einstellungen ↔ Preferences (globale Werte bleiben), tolerantes Dekodieren und Begrenzen, Speichern pro Skript ohne Änderungsdatum, Rundreise mit PDF ohne Bookmark des Absenders, Ablehnung fremder/neuerer/unvollständiger Dateien, sichere Dateinamen, Export und Import einer echten Präsentation mit Schritten (neue IDs, eigene PDF-Kopie), MCP-Rundreise `export_script` → `import_script`.
- Installierte App: macOS erkennt `.macprompter` als „macprompter-Skript“ (UTI `io.github.fng-2002.macprompter.script`) und ordnet die Dateien `/Applications/macprompter.app` zu.
- **Manuell offen:** Sichern (⇧⌘S) und Teilen über das Menü, Doppelklick im Finder (auch bei geschlossener Bibliothek), Import per ⌘O, Einstellungen wechseln beim Umschalten zwischen Skripten, Datei per AirDrop/Mail an einen zweiten Mac.

## Scrollrad in allen Modi · 27.10.2026

- 185 Tests bestanden, nichts übersprungen (Xcode 27.1, macOS 27.0), keine Compiler-Warnungen, iOS-App baut. Neu sind 6 Tests: Scrollrad in allen drei Modi und während Hover (Pause, Timer und Tastatur bleiben gesperrt), Raster = eine Zeile, Richtung wie `NSScrollView`, Countdown und ausgeblendeter Prompter sperren, Neuausrichtung der Sprachführung nach Scrollen unter Hover, Weiterleitung jedes Scroll-Ereignisses im Panel, globaler Monitor nur bei sichtbarem Prompter und eingeschalteter Option, abwärtskompatible `preferences.v1`.
- Die Scrollrichtung wurde gegen eine echte `NSScrollView` mit synthetischen Scroll-Ereignissen abgeglichen (negatives `scrollingDeltaY` → weiter im Text).
- **Manuell offen:** echtes Mausrad und Trackpad (inkl. Nachschwung), Zeiger über anderen Apps (Browser, Keynote) mit und ohne Option, natürliches Scrollen an/aus, Wiedereinstieg der Sprachführung nach Scrollen unter Hover mit echtem Mikrofon.

## Scrollrad außerhalb: Eingabeüberwachung · 27.10.2026

- Rückmeldung: Scrollen über dem Prompter funktioniert, außerhalb nicht. Ursache laut Systemprotokoll: Der WindowServer prüft für globale Scroll-Monitore `kTCCServiceListenEvent`; ohne Freigabe kommen keine Ereignisse an.
- 186 Tests bestanden, nichts übersprungen, iOS-App baut. Neu: Anfrage nur bei sichtbarem Prompter und eingeschalteter Option, keine Anfrage bei vorhandener Freigabe, Statuswechsel und Neuanlage des Monitors. Systemprotokoll bestätigt: Der Testlauf stellt keine echte Anfrage mehr.
- **Manuell offen:** Freigabe erteilen und Scrollen über anderen Apps prüfen (mit und ohne Neustart), Verhalten nach Neuinstallation einer neu gebauten Version.

## Folien folgen dem Lesefortschritt: Schalter · 27.10.2026

- Rückmeldung: Beim Scrollen über das iPhone wechselt die Folie, sobald der Text an einer Folienmarke vorbeiläuft. Das ist die bestehende Foliensynchronisation und gewünscht, soll aber global abschaltbar sein.
- 188 Tests bestanden, nichts übersprungen, iOS-App baut. Neu: Schalter aus in allen drei Modi (kein Wechsel über Stimme bzw. Fokuszeile, manuelle Wechsel samt Textsprung weiter möglich), Wiedereinschalten ab der nächsten Marke, abwärtskompatible `preferences.v1` (fehlend = an).
- **Manuell offen:** Präsentation mit iPhone-Scrollen und Scrollrad bei ausgeschaltetem Schalter.

## Folienwechsel beim Scrollen im Sprachmodus · 27.10.2026

- Rückmeldung: Im Modus Stimme wechselt die Folie beim Scrollen über eine Folienmarke nicht, nur im Modus Manuell. Ursache: Der Reader meldete die Fokuszeile im Sprachmodus grundsätzlich nicht.
- 189 Tests bestanden, nichts übersprungen. Neu: Scrollrad (unter Hover) und Tasten wechseln in allen drei Modi die Folie, mit ausgeschaltetem Schalter in keinem.
- **Manuell offen:** Präsentation im Sprachmodus mit Scrollrad und iPhone.

## Scrollrad überall per Event-Tap · 27.10.2026

- Rückmeldung: Scrollen außerhalb wirkte nur über scrollbaren Fenstern anderer Apps. Umstellung auf einen mitlesenden Event-Tap (ADR-16).
- Vom Maintainer mit einer installierten Testversion bestätigt: „jetzt klappt es genauso wie ich es mir vorgestellt habe“.
- 190 Tests bestanden, nichts übersprungen. Neu: Fensterregel des Taps (andere Apps/Schreibtisch und Präsentationsfenster ja, Prompter-Panel und übrige eigene Fenster nein).
- **Manuell offen:** Verhalten nach längerer Laufzeit (vom System deaktivierter Tap wird wieder eingeschaltet), Energieverbrauch.

## Laufzeit zurücksetzen · 27.10.2026

- Vom Maintainer mit installierter Testversion bestätigt (Knopf im Prompter und in der Referentenansicht).
- 191 Tests bestanden, nichts übersprungen. Neu: Zurücksetzen ändert nur die Uhr (Position, Folie, Wiedergabe bleiben), die Zeit läuft danach von 0 weiter, `AppModel.resetTimers` setzt Prompter- und Referentenuhr gemeinsam zurück.

## Wortverfolgung: Schreibweisen und Sprachdiagnose · 27.10.2026

- 209 Tests bestanden, nichts übersprungen (Xcode 27.1, macOS 27.0, lokale Sprachmodelle vorhanden), iOS-App baut, keine Compiler-Warnungen. Neu sind 18 Tests, davon 16 zur Wortverfolgung: Zahlen in beiden Richtungen (DE ein Wort, EN mehrere Wörter), Prozentzeichen, Abkürzungen, Komposita und Bindestriche, Kurzformen und knapp verfehlte Wörter, jeweils Wort für Wort eingespeist. Schutzfälle: kein Angleichen während eines Einschubs, wörtlich vorhandene Wörter bleiben unverändert, Skriptwörter mit Leerzeichen werden nicht zusammengezogen, eine entfernte Zahl allein löst keinen Sprung aus. Dazu Zahlenerkennung, Regeln für knapp verfehlte Wörter und Perzentile der Diagnose.
- Benchmark: 24 → 2 Wörter ohne Fortschritt bei 70 gehörten Wörtern, Zuordnungsdauer praktisch unverändert ([Messbericht](SPEECH_LATENCY_RESULTS.md)).
- 10-ms-Audioblöcke: im Echtzeitlauf mit den Fixtures Ergebnisse im Median rund 20 ms früher bei gleichem Text. Tests: Pegel mit 30 Hz und Spitzenwert, fortlaufende Audiozeit nach Eingangswechsel mit anderer Abtastrate. Korrektur am 28.10.2026: Mit echtem Mikrofon lieferte der Tap 102 ms; siehe den folgenden Abschnitt.
- Geprüft und verworfen: Skriptvokabular per `contextualStrings` (wirkt nur mit dem rund 140 ms langsameren `DictationTranscriber`, ADR-18) und Vorladen des Modells (Start nur 20–210 ms).
- **Manuell offen:** natürliches Sprechen mit echtem Mikrofon (Skript mit Zahlen, Abkürzungen, Namen); Werte der Sprachdiagnose während und nach einem Take, insbesondere „Audioblock“ des echten Mikrofons; AirPods oder Kopfhörer während eines Takes verbinden und trennen; Pegelanzeige im Overlay; Prüfen, dass knapp verfehlte Wörter keine falschen Vorsprünge auslösen.

## Geräteblöcke, Diagnose pro Wort, experimenteller Vorgriff · 28.10.2026

- Rückmeldung des Maintainers nach einem echten Take: kein deutlicher Unterschied, nicht schlechter. Die Diagnose zeigte 102 ms Audioblock, Erkennung Median 48 ms / p95 98 ms, Start 752 ms ([Messbericht](SPEECH_LATENCY_RESULTS.md)).
- Damals 226 Tests bestanden, nichts übersprungen (Xcode 27.1, macOS 27.0), iOS-App baut, keine Compiler-Warnungen. Neu waren 17 Tests: Ringpuffer der Sink-Aufnahme (jede Probe in Reihenfolge, außerhalb des Hauptthreads, Blöcke in Callback-Größe, Verwerfen statt Überschreiben), neuestes Wort eines Teilresultats, Ereignisse ohne Fortschritt nach Grund in einer echten Session, Wortlatenz in der Zusammenfassung. Vorlauf: Tempo, Begrenzung, Stopp nach 0,9 s, Stille, nie rückwärts, Pause außerhalb der Tempomessung, Stimmaktivität, Session mit und ohne Schalter, monotone Geometrie im echten Reader. Vormerkung: Anzeige und Bestätigung, Rücknahme, Stille, aus, Hover, schwächere Darstellung im Reader.
- **Manuell offen:** tatsächliche Blockgröße des Sink-Wegs mit dem eigenen Mikrofon, AirPods und externem Interface (Diagnose „Audioblock“); Rückfall auf den Tap bei einem Gerät, das den Sink-Weg ablehnt; beide experimentellen Schalter in echten Takes mit Pausen, Einschüben und Wiedereinstieg; Verhältnis bestätigter zu zurückgenommenen Vormerkungen; Stimmaktivität in lauter Umgebung.
- Zweiter Take des Maintainers: Audioblock 10,6 ms, Wortende → erkannt 6 / 15 ms, Erkennung 9 / 47 ms ([Messbericht](SPEECH_LATENCY_RESULTS.md)). Rückmeldung: „Nächstes Wort vormerken“ gefällt nicht und wurde vollständig entfernt (mit seinen 4 Tests). „Im Sprechtempo scrollen“ gefällt und ist jetzt eine Option unter Einstellungen → Lesen → Prompter, standardmäßig aus. Die Diagnose trennt „nicht zugeordnet“ in drei Gründe und zeigt den Mikrofonanteil der Startzeit.
- 222 Tests bestanden, nichts übersprungen, iOS-App baut, keine Compiler-Warnungen.
- **Manuell offen:** Markierung p95 und Startzeit in einem neuen Take; Option „Im Sprechtempo scrollen“ an der neuen Stelle.
- Dritter Take, wörtlich abgelesen: Markierung wieder 0,7 / 1,3 ms, Start 752 ms (Mikrofon 392 ms). Die 41 Ereignisse „Wort nicht im Skript“ führten zu halben Wörtern am Ende von Teilresultaten. Diese werden jetzt zurückgestellt; der Benchmark `FRAGMENT` zeigt 4 → 0 Hänger.
- 224 Tests bestanden, nichts übersprungen, iOS-App baut, keine Compiler-Warnungen. Neu: Wort für Wort eingespeister Strom mit halben Wörtern; ein Einschub, der mit einem Bruchstück endet, löst keinen Sprung aus. Alle bisherigen Schutztests bestehen.
- **Manuell offen:** nächster wörtlicher Take mit der Diagnose: Anteil mit Fortschritt und „Wort nicht im Skript“ im Vergleich zu 59 % / 41.
- Vierter Take, wörtlich abgelesen, vom Maintainer als „gefühlt schon schneller“ bewertet: 178 Ereignisse, 54 % mit Fortschritt, Wortende → erkannt 6 / 12 ms, Erkennung 8 / 23 ms, Zuordnung 0,53 / 0,94 ms, Markierung 0,7 / 1,6 ms, Audioblock 10,6 ms, Start 991 ms (Mikrofon 602 ms). Ohne Fortschritt: Wort nicht im Skript 39, noch nicht eindeutig 12, Einschub 16, Wiederholung 13, pausiert 1. „Wort nicht im Skript“ sinkt kaum, weil die meisten Teilresultate nur ein neues Wort bringen und ein alleinstehendes Bruchstück weiterhin nichts zu markieren hat. Die Korrektur wirkt, wenn ein fertiges Wort und ein Bruchstück zusammen ankommen.
- **Offen für eine nächste Runde:** 16 Ereignisse „Einschub“ trotz wörtlichem Lesen. Die Wortverfolgung hielt den Sprecher zeitweise für abgewichen und verlangte strengere Evidenz für den Wiedereinstieg.

## Erkenner-Takt, Zeit pro Wort, Diktiererkennung · 28.10.2026

- Fünfter Take des Maintainers: 156 Ereignisse, 60 % mit Fortschritt, Einschub 6 (vorher 16, schwankt zwischen Takes).
- Befund: Die Kennzahl „Wortende → erkannt“ war falsch. Pro Wort gemessen liefert `SpeechTranscriber` neue Wörter nur etwa alle 0,95 s; ein Wort erscheint im Median ~0,6 s nach seinem Ende. `DictationTranscriber` liefert alle ~0,25 s ([Messbericht](SPEECH_LATENCY_RESULTS.md), ADR-20).
- 228 Tests bestanden, nichts übersprungen (lokale Sprach- und Diktiermodelle vorhanden), iOS-App baut, keine Compiler-Warnungen. Neu: Echtzeit-Folgen mit dem Diktiermodell und Skriptvokabular (DE/EN, mit `WORD_LATENCY`), Wortlatenz-Zähler (Zuordnung über Wort und Zeit, Schübe, Pausen), Wortzeiten aus finalen Ergebnissen, Vokabularauswahl, Zusammenfassung von Wortlatenz und Takt.
- **Manuell offen:** echte Takes mit und ohne „Diktiererkennung mit Skriptvokabular“, je mit Diagnose (Wortende → erkannt, Neue Wörter alle, Ohne Fortschritt); Gefühl und Genauigkeit, besonders bei Zahlen und Namen; Download des Diktiermodells auf einem Mac ohne installiertes Modell.
- Sechster und siebter Take: ohne Diktat Takt 946 ms, Wort nach Ende 632 ms; mit Diktat 255 ms bzw. 436 ms, 70 % statt 60 % mit Fortschritt, kein Einschub. Urteil des Maintainers: „mit Schalter viel schneller und besser“. Daraufhin ist das Diktat Standard (abschaltbar unter Steuerung). Das Vokabular ist auf höchstens 50 seltene Wörter begrenzt, weil `setContext` den Start um ~5,5 ms pro Wort verlängert. Wörter, die erst im finalen Ergebnis erscheinen, werden getrennt gezählt.
- 229 Tests bestanden, nichts übersprungen, iOS-App baut, keine Compiler-Warnungen. Neu: Auswahl seltener Wörter über `NLEmbedding`.
- **Manuell offen:** Startzeit und Gefühl mit dem schmalen Vokabular; ein Skript mit vielen Namen; die einfache Erkennung nach dem Abschalten.
- Achter Take mit schmalem Vokabular: Takt 253 ms, Wort nach Ende Median 456 ms / p95 654 ms, 66 % mit Fortschritt, Start 1.290 ms (Mikrofon 419 ms). Der Start verzögert nur den Countdown; für den Maintainer kein Problem, deshalb kein Vorladen.

## Diktat und semantische Rückkehr immer aktiv · 28.10.2026

- Auf Wunsch des Maintainers (ADR-22): Die Schalter „Diktiererkennung mit Skriptvokabular“ und „Umformulierungen erkennen“ entfallen, beides ist immer aktiv. Aus „Experimentell“ wird „Diagnose“, neu ist die Zeile „Rückkehr per Satzmodell“.
- 229 Tests bestanden, nichts übersprungen, iOS-App baut, keine Compiler-Warnungen. Neu bzw. angepasst: Gespeicherte Werte der entfernten Schalter werden ignoriert und beim Speichern entfernt, alle übrigen Einstellungen bleiben; das Satzmodell wird nur im Modus Stimme gefragt; ein echter Modelltreffer wird gezählt; manuelles Verschieben entwertet eine laufende Modellantwort.
- **Manuell offen:** Einstellungsfenster ansehen (Bereich „Diagnose“, kein Schalter mehr unter Steuerung); ein Take mit bewusst umformulierten Sätzen, um „Rückkehr per Satzmodell“ zu sehen.

## MCP für Claude Desktop und Cowork (stdio-Helfer) · 01.11.2026

- 235 Tests bestanden, nichts übersprungen (Xcode 27.1, macOS 27.0), iOS-App baut, keine Compiler-Warnungen; `scripts/check.sh --release` erfolgreich, `codesign --verify --strict` prüft den eingebetteten Helfer mit. Neu: Konfiguration aus Umgebungsvariablen, Fehler als JSON-RPC-Antwort nur für Anfragen (falscher Token, unlesbare Zeile), ein einziger App-Start für gleichzeitige Anfragen mit Warten auf den Server, kein Warten bei laufender App mit ausgeschaltetem Zugang, Aufgeben nach der Frist, Ende-zu-Ende über Loopback mit echtem `MCPServer` (initialize, Benachrichtigung, `create_script`, falscher Token), Claude-Desktop-Konfiguration. Zufällige Testports werden bei Belegung neu gewählt (ein Release-Lauf scheiterte an einem belegten Port).
- Ende-zu-Ende mit der installierten App: Helfer mit Apple-Development-Signatur, eigener Sandbox und `network.client`. Bei beendeter App startete er macprompter und beantwortete `ping` nach etwa 2 s; Claude Code rief `list_scripts` über stdio korrekt auf, ebenfalls bei zuvor beendeter App. Beim ersten Start nach einem ad hoc signierten Testlauf fragte macOS einmal nach dem Zugriff auf den Container des Helfers.
- Maintainer am 01.11.2026: In Claude Desktop eingetragen, funktioniert in Cowork („klappt“).
- **Manuell offen:** Verhalten, wenn Claude Desktop startet, während macprompter nicht läuft; Präsentation per Cowork aus einer PDF im freigegebenen Ordner anlegen.


## Vorbereitung auf 1.0 · 09.11.2026

- Version 1.0.0 (Build 1) kommt jetzt für App, MCP-Helfer und iOS-App aus `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` im Projektgenerator. Einstellungen → Über macprompter zeigte vorher fest „0.1.0“.
- 239 Tests bestanden, nichts übersprungen (Xcode 27.1, macOS 27.0), iOS-App baut. Neu: Version und Build-Nummer im Bundle, mitgelieferte Lizenztexte (`Credits.html`, `OFL.txt`), Links des Hilfe-Menüs.
- Synthetische Testaudios werden mit `scripts/make_fixtures.sh` lokal erzeugt (ADR-24). Alle sechs `SpeechIntegrationTests` liefen mit den neu erzeugten Dateien grün, auch die beiden Echtzeit-Tests mit Einschub.
- In einer Demo-Variante des Debug-Builds (eigene Bundle-ID, nur Demo-Skripte) per Screenshot geprüft: Hilfe-Menü mit vier Einträgen, „Lizenzen und Danksagungen“ öffnet das About-Fenster mit Version 1.0.0 (1), Copyright und scrollbaren Lizenztexten, Einstellungen → Über macprompter mit Abschnitten Open Source, Entstehung und Software Dritter.
- **Manuell offen:** Links im Browser öffnen, sobald das Repository öffentlich ist (vorher zeigt GitHub für Außenstehende 404).

## Open Source und Release-Pipeline · 09.11.2026

- Keine Änderung am App-Code. Neu: Lizenz- und Beitragsdateien, `docs/AI.md`, README mit Medien, Release-Workflow mit `scripts/package_release.sh` und `scripts/release_notes.py`.
- Lokal geprüft: `scripts/package_release.sh` (ad hoc) baut eine universelle App (arm64 + x86_64), `codesign --verify --strict --deep` erfolgreich, `hdiutil verify` meldet eine gültige DMG (3,7 MB). `release_notes.py --check v1.0.0` erfolgreich, `--check v1.0.1` bricht wie erwartet ab; Notes für alle vier Signaturstufen erzeugt.
- Signatur mit selbst ausgestelltem Zertifikat lokal nur in einem temporären Schlüsselbund ausprobiert: Ohne Vertrauenseinstellung lehnt `codesign` die Identität ab. Auf dem Runner markiert der Workflow sie deshalb per `sudo security add-trusted-cert` als vertrauenswürdig; ob das dort funktioniert, zeigt erst ein Lauf mit gesetzten Secrets.
- Screenshots und Demo-Video aus einer Demo-Variante mit eigener Bundle-ID (`docs/MEDIA.md`); im Video sichtbar: Folienwechsel mit dem Lesefortschritt, Aufdeck-Schritte und „Hover-Pause“ im Prompter.
- **Manuell offen:** Release-DMG auf einem zweiten Mac installieren (Gatekeeper-Ablauf, Freigaben nach Update); Ansicht des README und der Release-Seite auf GitHub, sobald das Repository öffentlich ist.

## Release-Signatur auf dem Runner · 09.11.2026

- Erster Probelauf mit dem Projektzertifikat scheiterte am Import („MAC verification failed“): `security` auf dem macOS-26-Runner liest das Standardformat von OpenSSL 3 nicht. Der Workflow verpackt die `.p12` jetzt mit 3DES/SHA-1 neu; danach „1 identity imported“, Signatur `Authority=macprompter Release Signing`.
- Test-DMG aus dem Lauf heruntergeladen und geprüft: Prüfsumme stimmt, DMG und App signiert, `codesign --verify --strict --deep` erfolgreich, Designated Requirement `identifier "io.github.fng-2002.macprompter" and certificate leaf = H"be167ec…"` (stabil über Releases), Version 1.0.0, universell.
- Dabei gefunden: Release-App und Helfer trugen `com.apple.security.get-task-allow`. Jetzt `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` für Release; `package_release.sh` bricht ab, falls das Recht wieder auftaucht. Sauberer Release-Build lokal ohne `get-task-allow` geprüft.

## Neutrale Kennung und Neustart des Repositorys · 09.11.2026

- Kennungen auf `io.github.fng-2002.macprompter` umgestellt, Name des Maintainers aus Code, Doku und Lizenz entfernt (ADR-27). Die Vokabular-Tests nutzen jetzt erfundene Namen. 239 Tests bestanden, `scripts/check.sh --release` erfolgreich.
- Übernahme der Bibliothek des Maintainers: alle fünf Skripte per MCP als `.macprompter`-Dateien exportiert (Präsentation mit 31 Folien samt PDF und Einstellungen pro Skript), neue Version installiert, Dateien geöffnet; die Bibliothek zeigt danach alle fünf Skripte. Globale Einstellungen (Bildschirm, Spiegelung, Countdown), iPhone-Kopplung und MCP-Ordner sind neu einzustellen; der alte Container bleibt unverändert als Sicherung.

## Eine Signatur für Testversionen und Releases · 09.11.2026

- Projektzertifikat mit `scripts/make_signing_identity.sh --replace` neu ausgestellt, im Anmelde-Schlüsselbund als gültige Code-Signing-Identität vorhanden.
- `scripts/install.sh --quick` signiert mit „macprompter Release Signing“; ein Release-Probelauf auf GitHub erzeugt dieselbe Designated Requirement: `identifier "io.github.fng-2002.macprompter" and certificate leaf = H"910799…463f"`. Testversion und Release sind für macOS damit dieselbe App.
- **Manuell offen:** Nach dem nächsten Wechsel zwischen Testversion und Release bestätigen, dass macOS nicht erneut nach Mikrofon, Eingabeüberwachung oder Containerzugriff fragt.

## 1.0.0 mit dem neuen Zertifikat neu signiert · 09.11.2026

- Auf Wunsch des Maintainers wurde die DMG von 1.0.0 einmalig ersetzt, damit das Release dasselbe Zertifikat trägt wie lokale Testversionen (ADR-28). Gebaut per manuellem Workflow-Lauf aus dem unveränderten Tag `v1.0.0` (`efe0777`); Code und Release-Notes sind gleich, nur die Signatur ist neu. Die alte DMG war zu diesem Zeitpunkt zweimal geladen worden, einmal davon bei der eigenen Prüfung.
- Nach dem Austausch von GitHub geladen: Prüfsumme `80e5f9b5…0197e1` stimmt, Datei identisch mit dem geprüften Build, `Authority=macprompter Release Signing`, Designated Requirement gleich der installierten Testversion (`certificate leaf = H"910799…463f"`), ohne `get-task-allow`.
- Ausnahme von der Regel in docs/RELEASING.md; künftige Korrekturen erscheinen wieder als neue Version.
