# iPhone-Fernbedienung (macprompter Remote)

Stand: 26. Oktober 2026 · Issue #2 · Entscheidung: [ADR-9](DECISIONS.md)

macprompter Remote ist eine native iOS-26-App, die den Prompter auf dem Mac im lokalen Netz steuert: Start, Pause, Ausblenden, Skriptwahl, Modus, Tempo, manuelles Scrollen und PDF-Folien. Auf dem Mac ist die Funktion **standardmäßig aus** (Einstellungen → iPhone-Fernbedienung).

## Aufbau

| Datei | Aufgabe |
| --- | --- |
| `Shared/RemoteProtocol.swift` | Nachrichten, Status, Befehle, Längenpräfix-Framing, Scroll-Bündelung |
| `Shared/RemotePairing.swift` | Code, PBKDF2-Kopplungsschlüssel, HMAC-Nachweise, X25519-Geräteschlüssel, Kopplungsfenster |
| `Shared/RemoteTransport.swift` | `NWParameters` mit TLS-PSK, `RemoteChannel` (eine Verbindung, Callbacks auf dem Main-Thread) |
| `Shared/RemoteClient.swift` | iPhone-Seite: Bonjour-Suche, Kopplung, Sitzung, automatisches Wiederverbinden |
| `MacPrompter/Services/RemoteServer.swift` | Mac-Seite: `NWListener` mit Bonjour, Kopplungsfenster, Geräteliste, Status-Push |
| `MacPrompter/Services/RemoteControl+AppModel.swift` | `RemoteBridge`: die einzige Stelle, an der Fernbefehle App-Zustand ändern |
| `MacPrompter/Views/RemoteSettingsSections.swift` | Einstellungsbereich auf dem Mac |
| `MacPrompterRemote/` | iOS-App (SwiftUI): Mac-Liste, Kopplung, Steueransicht mit drei Layouts, Schlüsselbund |

`Shared/` wird in beide Apps kompiliert. Damit läuft die gesamte Protokoll-, Kopplungs- und Client-Logik auch in der macOS-Testsuite, einschließlich eines echten Loopback-Durchlaufs gegen den Server (`RemoteServerTests`). Die iOS-App selbst enthält nur Oberfläche und Schlüsselbund-Speicher und wird von `scripts/check.sh` für den Simulator gebaut.

## Bewegung und Sperre

Alle Befehle gehen durch `RemoteBridge` an `PrompterSession` bzw. `PreferenceStore`:

- **Start** zeigt das gewählte Skript an und startet es (idempotent, kein Umschalten). **Pause** und **Ausblenden** entsprechen ⌥⌘P bzw. ⌥⌘H.
- **Scrollen** ruft `session.nudge(_:)` auf. Damit gilt die `PlaybackGate`: Hover, Countdown und ausgeblendeter Prompter verwerfen Fernbefehle genau wie die Tastatur. (Das Scrollrad am Mac wirkt seit ADR-13 auch während Hover, weil es eine direkte Geste am Prompter ist.) Schritte sind auf ±400 pt begrenzt; die Wischfläche bündelt Bewegungen auf höchstens ~30 Nachrichten pro Sekunde.
- **Tempo** wird auf 10…120 pt/s begrenzt und gerundet, **Modus** wie in der Konfigurationsleiste gesetzt (ein Moduswechsel pausiert).
- **Folien** nutzen `session.stepSlide(±1)` – derselbe Weg wie Pfeiltasten und Presenter-Fernbedienung: Die Folie wechselt immer, der Text springt nur, wenn die Sperre Bewegung erlaubt. **Präsentation starten/beenden** ruft `AppModel.startPresentation()`/`endPresentation()`. Hat das Skript der Sitzung keine PDF, meldet der Status `slides = nil` und das iPhone graut die Folienbedienung aus.

## Welche Daten das iPhone erhält

Nur, was die Bedienung braucht: Skripttitel (Liste zur Auswahl), Status-Text der Sitzung, sichtbar/läuft/Hover/Countdown/Vorbereitung, Modus, Tempo, Fortschritt (auf 0,1 % gerundet), Laufzeit in Sekunden, Folie x/y und ob präsentiert wird. **Keine Skripttexte, kein Audio, keine Transkripte.** Ein Test (`testStatusCarriesTitlesButNeverScriptText`) prüft das am kodierten JSON.

Der Status wird bei jedem Befehl sofort und sonst alle 250 ms gesendet, aber nur, wenn sich etwas geändert hat und mindestens ein Gerät verbunden ist. Der Scroll-Offset ist absichtlich nicht beobachtbar (Display-Link-Takt), deshalb diese Abfrage statt Beobachtung.

## Transport

- Bonjour-Dienst `_macprompter._tcp`, TXT-Felder `v` (Protokollversion), `id` (zufällige Server-ID), während der Kopplung zusätzlich `pair=1` und `salt`.
- `includePeerToPeer = true`: iPhone und Mac finden sich auch ohne gemeinsames WLAN über Apples Peer-to-Peer-WLAN (AWDL), solange WLAN auf beiden Geräten an ist. Kein Internet, keine Cloud, keine Relays.
- Der Listener nimmt nur Verbindungen aus dem lokalen Netz an (`acceptLocalOnly`) und läuft nur, solange die Fernsteuerung eingeschaltet ist. Er behält bei Schlüsseländerungen seinen Port.
- Nachrichten: 4-Byte-Längenpräfix (Big Endian) + JSON, höchstens 64 KB pro Nachricht. Unbekannte Nachrichten einer neueren Gegenseite werden übersprungen, nicht als Fehler gewertet.

## Kopplung und Verschlüsselung

1. Der Nutzer wählt am Mac „iPhone koppeln …“. Der Mac erzeugt einen **sechsstelligen Code** (`SystemRandomNumberGenerator`) und ein zufälliges 16-Byte-Salt. Das Fenster ist **2 Minuten** offen und schließt nach **5 Fehlversuchen** (fehlgeschlagene TLS-Handshakes oder falsche Nachweise).
2. Beide Seiten leiten aus Code und Salt per **PBKDF2-SHA256 (200 000 Iterationen)** einen 256-Bit-Kopplungsschlüssel ab. Der Mac ergänzt ihn für die Dauer des Fensters als zusätzlichen Pre-Shared Key (Identität `macprompter-pairing-v1`).
3. Das iPhone verbindet sich per TLS mit diesem Schlüssel. Der Mac sendet eine Zufalls-Challenge; das iPhone antwortet mit einem HMAC-Nachweis und einem frischen **X25519**-Schlüssel.
4. Der Mac antwortet mit einer neuen Geräte-ID und seinem X25519-Schlüssel. Beide berechnen den **256-Bit-Geräteschlüssel** per HKDF aus dem gemeinsamen Geheimnis, gebunden an Kopplungsschlüssel, Geräte-ID und beide öffentlichen Schlüssel. **Der Geräteschlüssel wird nie übertragen.**
5. Der Mac schließt das Fenster und startet den Listener mit dem neuen Geräteschlüssel (Identität = Geräte-ID). Das iPhone verbindet sich damit; jede Sitzung beginnt mit Challenge und HMAC-Nachweis, damit der Mac weiß, welches Gerät spricht.

Gekoppelte Geräte stehen am Mac in der Liste (Name, Kopplungsdatum, zuletzt gesehen, verbunden). **Entfernen** löscht den Schlüssel, trennt das Gerät sofort und startet den Listener ohne diesen Schlüssel neu; das iPhone wird danach schon im TLS-Handshake abgewiesen. Auf dem iPhone kann eine Kopplung per Wischgeste entfernt werden (das entfernt sie nicht am Mac).

### Gemessen: TLS 1.2 statt TLS 1.3

Vorgabe war TLS 1.3 mit Pre-Shared Key. Network.framework verhandelt mit externem PSK auf macOS 27 / Xcode 27.1 jedoch ausschließlich **TLS 1.2 mit `TLS_PSK_WITH_AES_128_GCM_SHA256` (0x00A8)**: Mit erzwungener Mindestversion 1.3 und nur TLS-1.3-Suiten scheitert der Handshake; angehängte ECDHE-PSK-Suiten (0xCCAC, 0xC037, 0xC035) und TLS-1.3-Suiten werden ignoriert, ausgehandelt wurde in allen Varianten 0x0303/0x00A8. Mehrere PSK-Identitäten pro Listener und das Überleben angenommener Verbindungen beim Listener-Neustart wurden im selben Versuch bestätigt.

Folgen und Ausgleich:

- Die Verbindung ist mit AES-128-GCM vertraulich und integritätsgeschützt, hat aber **keine Forward Secrecy**: Wer später einen Geräteschlüssel erbeutet, könnte zuvor mitgeschnittene Sitzungen dieses Geräts entschlüsseln. Inhalt wären Befehle, Titel und Status – keine Skripttexte.
- Gegen das größere Risiko – einen mitgeschnittenen Kopplungs-Handshake, dessen sechsstelliger Code offline durchprobiert wird – hilft die X25519-Vereinbarung: Selbst mit gefundenem Code sieht ein passiver Lauscher nur öffentliche Schlüssel und kann den Geräteschlüssel nicht berechnen.

Reproduktion: Ein kleines Swift-Programm mit `NWListener`/`NWConnection` auf 127.0.0.1, `sec_protocol_options_add_pre_shared_key` und Ausgabe von `sec_protocol_metadata_get_negotiated_tls_protocol_version` bzw. `…_ciphersuite` (Varianten: Mindestversion 1.3, nur `TLS_AES_128_GCM_SHA256`, zusätzliche ECDHE-PSK-Suiten).

## Grenzen (ehrlich)

- **Kurzer Code während der Kopplung.** Sechs Ziffern sind 10⁶ Möglichkeiten. Ein **aktiver** Angreifer im selben Netz, der genau während der zwei Minuten den Handshake des iPhones abfängt, könnte den Code aus dem TLS-PSK-Handshake offline erraten (PBKDF2 kostet pro Versuch Rechenzeit, verhindert es aber nicht) und sich als Mann in der Mitte einklinken. Das ist kein PAKE-Verfahren. Empfehlung in der App: nicht in fremden oder öffentlichen Netzen koppeln; unbekannte Geräte in der Liste entfernen. Ein Vergleichscode auf beiden Bildschirmen wäre eine mögliche spätere Härtung.
- **Online-Raten** ist durch 5 Versuche pro Code und 2 Minuten begrenzt.
- **Schlüsselablage auf dem Mac:** `remote-devices.json` (Dateirechte 0600) im Sandbox-Container der App, nicht im Schlüsselbund. Grund: Die App ist ad hoc signiert; Schlüsselbund-Zugriffsregeln hängen an der Signatur und würden nach jedem Build erneut nachfragen. Der Container ist durch die Sandbox vor anderen Apps geschützt, nicht aber vor Prozessen mit Vollzugriff auf die Festplatte oder vor Backups. Eine unlesbare Datei wird nie überschrieben.
- **Schlüsselablage auf dem iPhone:** Schlüsselbund, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, keine iCloud-Synchronisation.
- **Sichtbarkeit:** Die TLS-PSK-Identität (zufällige Geräte-ID) und der Bonjour-Name des Macs sind im lokalen Netz im Klartext sichtbar.
- **Nur im Vordergrund:** Die iOS-App hält keine Hintergrundverbindung; beim Wechsel in den Hintergrund trennt sie, beim Zurückkehren verbindet sie sich automatisch mit dem zuletzt genutzten Mac. Während einer Verbindung bleibt der iPhone-Bildschirm an.
- **Gerätename:** iOS liefert ohne besonderes Entitlement nur „iPhone“; die Geräteliste unterscheidet mehrere iPhones über Kopplungsdatum und „zuletzt gesehen“.
- **Nur iPhone:** Die App ist für iPhone gebaut (`TARGETED_DEVICE_FAMILY = 1`), nicht für iPad optimiert.

## Berechtigungen

- **Mac:** `com.apple.security.network.server` (Listener). Nur die Debug-Konfiguration – zugleich Test-Host – hat zusätzlich `com.apple.security.network.client`, weil der Loopback-Test aus der Sandbox heraus eine Verbindung zum eigenen Listener öffnet. Die ausgelieferte Release-App kann keine ausgehenden Verbindungen öffnen. `Info.plist`: `NSLocalNetworkUsageDescription`, `NSBonjourServices`.
- **iPhone:** keine Entitlements; `NSLocalNetworkUsageDescription` und `NSBonjourServices` lösen beim ersten Suchen die Abfrage „Lokales Netzwerk“ aus. Wird sie abgelehnt, zeigt die App einen Hinweis mit Link in die Einstellungen.

## Bedienung auf dem iPhone

- **Mac-Liste:** gefundene Macs mit Status (gekoppelt / bereit zum Koppeln / nicht gekoppelt), nicht erreichbare gekoppelte Macs, Hinweis bei verweigertem lokalem Netzwerk.
- **Kopplung:** Codefeld mit Ziffernblock und Einmalcode-Unterstützung, Fehlermeldung bei falschem oder abgelaufenem Code.
- **Steuerung:** Statuskarte (Skript, Laufzeit, Fortschritt, Zustand inkl. Hover-Hinweis), Transport (Ausblenden, Start/Pause, Skriptwahl), Tempo (Modus, Schieberegler, langsamer/schneller), Scrollen (Schritt-Tasten und Wischfläche, mit Grund, wenn gesperrt), Folien.
- **Layouts** (oben rechts, lokal gespeichert): *Alles*, *Tempo und Text* (ohne Folien) und *Nur Folien* (großer Klicker mit großer Weiter- und kleinerer Zurück-Fläche).
- Liquid-Glass-Schaltflächen (`.glass`, `.glassProminent`), SF Symbols, Dynamic Type (`@ScaledMetric`), VoiceOver-Beschriftungen (Wischfläche als anpassbares Element), Haptik bei Tasten, Folien und erfolgreicher Verbindung, helles und dunkles Erscheinungsbild.

## iOS-App bauen und starten

```sh
python3 scripts/generate_project.py
xcodebuild build -project MacPrompter.xcodeproj -scheme "macprompter Remote" \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build
xcrun simctl boot "iPhone 17 Pro"   # beliebiger iOS-26-Simulator
xcrun simctl install booted "build/Build/Products/Debug-iphonesimulator/macprompter Remote.app"
xcrun simctl launch booted io.github.fng-2002.macprompter.remote
```

Für ein echtes iPhone `MacPrompterRemote/Signing.local.xcconfig` anlegen (wird nicht eingecheckt) und das Projekt in Xcode mit dem Schema **macprompter Remote** auf dem Gerät starten:

```
DEVELOPMENT_TEAM = ABCDE12345
CODE_SIGN_STYLE = Automatic
CODE_SIGN_IDENTITY = Apple Development
```

Ist die Bundle-ID `io.github.fng-2002.macprompter.remote` im eigenen Team nicht verfügbar, dort zusätzlich `PRODUCT_BUNDLE_IDENTIFIER` überschreiben. Ohne diese Datei baut das Projekt für den Simulator ad hoc signiert und für Geräte nur mit `CODE_SIGNING_ALLOWED=NO` (so prüft es `scripts/check.sh --release`).

## Manuelle Ende-zu-Ende-Prüfung (nur Debug-Builds)

Agents können weder den Mac-Bildschirm lesen noch im Simulator tippen. Für einen echten Lauf über Bonjour gibt es deshalb zwei Startargumente, die nur in Debug-Builds existieren (`#if DEBUG`):

- Mac: `macprompter.app/Contents/MacOS/macprompter -RemoteDebugPairing YES` startet den Listener ohne die Präferenz zu ändern, öffnet ein Kopplungsfenster und schreibt `REMOTE_PAIRING_CODE <code>` auf stderr.
- iPhone/Simulator: `xcrun simctl launch booted io.github.fng-2002.macprompter.remote -RemoteDebugPairCode <code>` koppelt automatisch mit dem ersten Mac, der einen Code anbietet.

Achtung: Der Lauf legt `remote-devices.json` im echten Container der App an; danach am Mac das Gerät entfernen oder die Datei löschen.

