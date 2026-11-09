# Screenshots und Demo-Video

Die Bilder in `docs/media/` entstanden am 9. November 2026 auf macOS 27.0 mit einem externen 2560 × 1440-Bildschirm (ohne Notch; der Prompter sitzt dann oben in der Mitte). Sie zeigen nur Demo-Inhalte, nie echte Nutzerdaten.

| Datei | Inhalt |
| --- | --- |
| `demo.gif` | Präsentation mit Prompter im Modus Automatisch, doppelte Geschwindigkeit, Ausschnitt 1920 × 1080 |
| `macprompter-demo.mp4` | 41-Sekunden-Demo ohne Ton: Titel, Bibliothek, Folien-Editor, Präsentation mit Folienwechsel und Hover-Pause, Hinweis auf den Modus Stimme |
| `library.png`, `slide-editor.png`, `settings.png`, `presenting.png` | Bibliothek, Folien-Editor, Einstellungen → Lesen, Präsentation mit Prompter |

Die Sprachsteuerung ist im Video nur als Texttafel erwähnt, weil sie ein echtes Mikrofon braucht und synthetische Systemstimmen nicht veröffentlicht werden dürfen (ADR-24).

## Neu aufnehmen

1. **Demo-Variante bauen**, damit die eigene Bibliothek unberührt bleibt (eigene Bundle-ID, eigener Container):
   ```sh
   xcodebuild build -project MacPrompter.xcodeproj -scheme macprompter -configuration Debug \
     -destination 'platform=macOS,arch=arm64' -derivedDataPath build/demo \
     PRODUCT_BUNDLE_IDENTIFIER=io.github.fng-2002.macprompter.demo
   open -n build/demo/Build/Products/Debug/macprompter.app --args -MCPDebugPort 47611 -OverlayCapturable YES
   ```
   `OverlayCapturable` gibt es nur im Debug-Build: Er hebt den Aufnahmeschutz des Prompters auf, damit er auf Screenshots erscheint. `MCPDebugPort` schaltet den MCP-Zugang ein, ohne die Einstellungen zu ändern.
2. **Demo-Inhalte** über MCP anlegen (`create_script`, `create_presentation` mit `MacPrompter/Resources/Templates/Beispiel-Praesentation.pdf` und den Texten aus `Templates.swift`); Token in `~/Library/Containers/io.github.fng-2002.macprompter.demo/Data/Library/Application Support/macprompter/mcp.json`.
3. **Aufnehmen** (das Terminal braucht die Freigaben Bildschirmaufnahme und, für Klicks per Skript, Bedienungshilfen): Fenster mit `screencapture -x -o -l <Fenster-ID>`, Präsentation mit `screencapture -x -v -C -V 55 rec.mov`.
4. **Tafeln und Untertitel** rendern: `swiftc -O scripts/media/PromoCards.swift -o build/promo-cards && build/promo-cards <ordner> <icon.png> library.png "…" shot-library slide-editor.png "…" shot-editor`.
5. **Schneiden** mit `ffmpeg` (H.264, 1920 × 1080, 30 fps, ohne Ton): Tafel 3 s, zwei Screenshots je 3,5 s, Aufnahme ab Sekunde 2 mit doppelter Geschwindigkeit (24 s) und drei Untertiteln, zwei Tafeln je 3,5 s. GIF: dieselbe Aufnahme, 12 fps, Ausschnitt `crop=1920:1080:120:0`, 960 px breit, Palette mit 96 Farben.
