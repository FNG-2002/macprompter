# Architektur

Stand: 25. Oktober 2026. Überblick für Menschen und Agents; Details zu Algorithmen stehen in den verlinkten Fachdokumenten.

## Schichten

```
MacPrompterApp ─ AppDelegate
      │
   AppModel (@MainActor, Singleton)
      ├── PreferenceStore ── UserDefaults "preferences.v1"
      ├── ScriptLibrary ──── Application Support/macprompter/scripts.json
      ├── PrompterSession ── SpeechService ── AVAudioEngine → MicrophoneConverter → SpeechAnalyzer (Recognizer: SpeechTranscriber oder DictationTranscriber)
      │        ├── ScriptFollower (Wortausrichtung, value type) ── LexicalBridge (Schreibweisen)
      │        ├── ReadingLead + VoiceActivity (Scrollen im Sprechtempo, ADR-19)
      │        ├── SemanticScriptIndex + AppleSemanticRecovery (actor, optional)
      │        └── SpeechLatencyMetrics (in-memory, Zusammenfassung in den Einstellungen)
      ├── OverlayController ── PrompterPanel (NSPanel) ── OverlayView ── ReaderView/ReaderViewport
      ├── PresentationFiles ── PDF-Kopien, Bookmarks, Fingerabdrücke, Thumbnails
      ├── PresentationController ── Folienfenster (AudienceView) + Referentenansicht
      ├── RemoteServer (opt-in) ── NWListener/Bonjour, TLS-PSK ── RemoteBridge → Session/Präferenzen
      │        ⇅ lokales Netz / AWDL
      │   macprompter Remote (iOS) ── RemoteClient (Shared/) ── SwiftUI
      ├── MCPServer ── HTTP auf 127.0.0.1 ── JSON-RPC ── AgentTools (Skripte/Präsentationen bearbeiten)
      └── GlobalShortcuts (Carbon-Hotkeys)
```

- **Core** (`MacPrompter/Core`): Domänenlogik ohne Fenster. `ScriptParser` (`Core/ScriptText.swift`), `ScriptFollower` und `LexicalBridge` sind reine Werttypen ohne App-Abhängigkeiten und lassen sich ohne App testen bzw. per `swiftc` benchmarken.
- **Services** (`MacPrompter/Services`): Systemanbindungen – Mikrofon/Speech, Satzmodelle, Overlay-Fenster, Hotkeys.
- **Views** (`MacPrompter/Views`): SwiftUI-Oberfläche; Text-Rendering und Editor über `NSTextView` in `NSViewRepresentable`.

## Zentrale Abläufe

### Prompter anzeigen und starten

`AppModel.toggle()` → `PrompterSession.present(script)` setzt `gate.isVisible` und meldet über `onVisibilityChange` an den `OverlayController`, der das nicht aktivierende Panel positioniert (Notch oder frei) und `OverlayView` hostet. `togglePlayback()` startet Countdown und – im Modus Stimme – `SpeechService.start(language:)`.

### Bewegung: eine Uhr, eine Sperre

- `ReaderViewport` besitzt einen `CADisplayLink` am eigenen Bildschirm. Er ruft `session.advanceFrame(by:)` und schreibt den Offset direkt in die `NSClipView` – ohne SwiftUI-Durchlauf. Bei Pause, Hover oder Vorbereitung ist der Link pausiert.
- `PlaybackGate` (`Core/Script.swift`) ist die **einzige** Sperre für Timer, Sprache, Tasten und Scrollrad: `allowsMovement` / `allowsAutomaticMovement` / `allowsScrolling`. Neue Bewegungsquellen müssen sie verwenden. Das Scrollrad (`PrompterSession.scrollWheel`) nutzt `allowsScrolling` und wirkt damit auch während der Hover-Pause (ADR-13). `PrompterPanel.sendEvent` fängt Scroll-Ereignisse im ganzen Overlay ab; `OverlayController` hält zusätzlich einen mitlesenden Event-Tap (`ScrollWheelTap`, ADR-16), solange der Prompter sichtbar und „Scrollrad außerhalb“ eingeschaltet ist. Er sieht jedes Scroll-Ereignis, auch über nicht scrollbaren Flächen und den Präsentationsfenstern; über dem Prompter und den übrigen eigenen Fenstern ignoriert er sie (`tapHandlesScroll`). Er braucht die Freigabe „Eingabeüberwachung“ (ADR-14); `AppModel.scrollAccessGranted` spiegelt sie für die Einstellungen.
- Modi: `automatic` (konstante Geschwindigkeit), `manual` (`nudge`), `voice` (Scrollziel aus erkannten Wörtern, weich angefahren über `ReadingMotion`).

### Sprache → Markierung → Scrollziel

1. `SpeechService` liest das Mikrofon über `AudioSinkCapture` (`AVAudioSinkNode`, Geräteblöcke ~10 ms; der Echtzeit-Callback kopiert nur in einen Ringpuffer, ein Worker-Thread wandelt um; Rückfall auf `installTap`), gibt das Audio an `SpeechAnalyzer` und liefert veränderliche und finale Teilresultate mit Segment-ID und Audio-Endzeit an `PrompterSession.receiveTranscript`. Bei einem Eingangswechsel (`AVAudioEngineConfigurationChange`) hängt es den neuen Eingang an denselben Analyzer; die Audiozeit läuft weiter.
2. Ergebnisse vor `ignoreSpeechThrough` (Hover, Pause, manuelle Navigation, Countdown) werden verworfen.
3. `ScriptFollower.consume` gleicht zuerst die Schreibweise gehörter Wörter an das Skript an (`LexicalBridge`: Zahlen, Abkürzungen, Komposita, knapp verfehlte Wörter) und richtet dann die letzten bis zu zwölf gehörten Wörter am Skript aus: lokal → flexibel lokal → global, mit dauerhaftem Anker für Einschübe. Siehe [SPEECH_FOLLOWING.md](SPEECH_FOLLOWING.md).
4. Treffer: `activeWordRange` (Markierung) und `targetCharacter` (nächstes Wort). Der Reader löst `targetCharacter` in eine Pixelposition auf (`resolveVoiceDestination`), die der Display-Link anfährt.
5. Kein Treffer und Option „Umformulierungen erkennen“ aktiv: asynchrone Anfrage an `AppleSemanticRecovery` (eine laufende + eine ersetzbare Anfrage, Ergebnisse > 250 ms oder mit veralteter Revision werden verworfen). Siehe [SEMANTIC_RECOVERY.md](SEMANTIC_RECOVERY.md).

### PDF-Präsentationen

`Script.presentation` (optional) enthält Seiten-Fingerabdrücke und Abschnitte. `PresentationComposer` leitet daraus `Script.body` mit Start- und „Nächste Folie“-Cues ab sowie eine `SlideTimeline` (Zeichen → Seite). Die Session hält `currentSlide`: Im Sprachmodus folgt er dem nächsten zu sprechenden Wort, in den Scroll-Modi meldet der Reader die Fokuszeile. `stepSlide` wechselt manuell und setzt `jumpCharacter`, das der Reader über die `PlaybackGate` in einen Offset auflöst. PDF-Updates richtet `SlideMatcher` aus, ohne Text zu verlieren. Die Präsentationsfunktionen des `AppModel` stehen in `AppModel+Presentation.swift`. Siehe [PRESENTATIONS.md](PRESENTATIONS.md).

### iPhone-Fernbedienung

`RemoteServer` (`Services/`) existiert nur bei eingeschalteter Option und wirbt per Bonjour `_macprompter._tcp`. Jede Verbindung beginnt mit TLS (Pre-Shared Key pro Gerät) und einem HMAC-Nachweis auf eine Challenge. Befehle laufen ausschließlich über `RemoteBridge` (`Services/RemoteControl+AppModel.swift`) zu `PrompterSession` (`nudge`, `stepSlide`, `togglePlayback`) bzw. `PreferenceStore`; die `PlaybackGate` gilt damit unverändert. Der Status wird bei Befehlen sofort und sonst mit 4 Hz nur bei Änderungen gesendet. Protokoll, Kopplung und Client liegen in `Shared/` und werden in beide Apps kompiliert, damit die macOS-Testsuite auch den iOS-Client prüft. Siehe [REMOTE.md](REMOTE.md).

### Zugang für KI-Agenten (MCP)

`MCPServer` nimmt JSON-RPC über `POST /mcp` auf 127.0.0.1 an (eigener HTTP/1.1-Parser auf `NWListener`, Token, Origin-/Host-Prüfung). `AgentTools` setzt die Werkzeuge über `ScriptLibrary` und `PresentationFiles` um, also dieselben Wege wie die Oberfläche; eine sichtbare Sitzung wird nach Änderungen neu geladen. `JSONValue` ist der Sendable-JSON-Typ dafür. Für Claude Desktop und Cowork, die nur lokale Programme per stdio starten, liegt das Hilfsprogramm `macprompter-mcp` (eigenes Target `MacPrompterMCP/`, eigene Sandbox mit `network.client`) in `Contents/Helpers`; `MCPBridge` reicht dort jede stdin-Zeile an `POST /mcp` weiter und startet die App bei Bedarf. Siehe [MCP.md](MCP.md).

### Persistenz

- `ScriptLibrary`: JSON-Array von `Script`, entprellt (400 ms) und atomar geschrieben. Ist die Datei nicht lesbar, wird `canSave = false` gesetzt und nie überschrieben.
- PDF-Kopien: `Presentations/<deck-id>.pdf` neben `scripts.json`. Original per Security-Scoped Bookmark.
- `Script.settings` (optional): Seitenleisten-Einstellungen pro Skript. Die globalen `Preferences` bleiben die Laufzeitquelle; `AppModel` überträgt sie beim Auswählen eines Skripts in die Preferences und speichert Änderungen zurück ins ausgewählte Skript (`AppModel+ScriptFiles.swift`).
- `.macprompter`-Dateien (`ScriptDocument`, UTI `io.github.fng-2002.macprompter.script`): ein JSON-Dokument mit Skript, Einstellungen und eingebetteter PDF, ohne Bookmarks; Import vergibt neue IDs und eine neue PDF-Kopie.
- Fernbedienung: `remote-devices.json` (Server-ID, Geräte mit Schlüssel, 0600) neben `scripts.json`; nicht lesbar → nie überschrieben. Auf dem iPhone: Schlüsselbund (nur dieses Gerät), Layout in `UserDefaults`.
- `PreferenceStore`: ein JSON-Blob unter `preferences.v1`. Neue Felder müssen optional dekodierbar sein, damit alte Daten nicht auf Defaults zurückfallen.

## Nebenläufigkeit

- App-Zustand ist `@MainActor @Observable`. Hochfrequente Werte (`offset`, `elapsed`) sind `@ObservationIgnored` und werden per Callback weitergereicht.
- Der Mikrofon-Tap (`MicrophoneTap.make`) ist bewusst `nonisolated` und läuft auf der Audio-Queue; nur `Sendable`-Callbacks gehen zurück zur UI.
- `NLEmbedding` ist nicht threadsicher und lebt ausschließlich im `actor AppleSemanticRecovery`.
- Strikte Concurrency-Prüfung (`complete`) ist aktiv; neue Warnungen gelten als Fehler im Sinne der Review.

## Fenster und System

- `PrompterPanel`: `.nonactivatingPanel`, `canBecomeKey = false`, über allen Spaces und Vollbild-Apps; im Notch-Modus oberhalb der Menüleiste. `sharingType = .none` ist nur ein Best-Effort-Aufnahmeschutz.
- Bildschirmwechsel (`didChangeScreenParametersNotification`) und Präferenzänderungen lösen `reposition()` aus; das Hosting-View und der Reader bleiben dabei erhalten.
- Globale Hotkeys über Carbon `RegisterEventHotKey` – keine Accessibility-Berechtigung nötig. Folien-Hotkeys (⌥⌘←/→) existieren nur während einer Präsentation; mehrere `GlobalShortcuts`-Instanzen reichen fremde IDs weiter.
- Präsentation: randloses Folienfenster auf normaler Ebene (Prompter-Panel bleibt darüber), optional Referentenansicht als normales Fenster; ein lokaler Key-Monitor bedient Tasten und Presenter-Fernbedienungen.
- Systemruhezustand und App-Ende blenden den Prompter aus und stoppen das Mikrofon.

## Build

Das Xcode-Projekt wird von `scripts/generate_project.py` erzeugt (stabile IDs, keine Zusatzpakete). Ziele: `macprompter` (App, Bundle-ID `io.github.fng-2002.macprompter`; Debug mit `MacPrompterDebug.entitlements`, das zusätzlich `network.client` für den Loopback-Test enthält), `MacPrompterTests` (Unit-Tests mit App als Host) und `macprompter Remote` (iOS 26, Bundle-ID `io.github.fng-2002.macprompter.remote`, Signatur über `MacPrompterRemote/Signing.xcconfig` plus optionales, nicht eingechecktes `Signing.local.xcconfig`). `Shared/**/*.swift` gehört zu beiden Apps. Einheitliche Prüfung: `scripts/check.sh` (Mac-Tests + iOS-Simulator-Build).

Version und Build-Nummer stehen einmal im Generator (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`). Die synthetischen Testaudios erzeugt `scripts/make_fixtures.sh` lokal (ADR-24). Releases: `.github/workflows/release.yml` ruft bei einem Tag `scripts/check.sh`, `scripts/package_release.sh` (universeller Release-Build, Signatur, DMG) und `scripts/release_notes.py` (Prüfung von Tag/Version/CHANGELOG, Release-Notes) auf; Ablauf in [RELEASING.md](RELEASING.md), Entscheidung in ADR-26.
