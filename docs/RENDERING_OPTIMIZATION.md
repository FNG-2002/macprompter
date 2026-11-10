# Scrollen und Aktualisierungen · 5. Oktober 2026

Die automatische Bewegung verwendet jetzt einen an den Reader gebundenen AppKit-Display-Link. Dieser folgt dem Bildschirm des Views auch bei Monitorwechseln. Der bisherige feste 60-Hz-Timer in der Sitzung entfällt. Es läuft keine zweite Scroll-Uhr nebenher. Bei Pause, Hover oder während der Vorbereitung pausiert der Link; beim Entfernen aus dem Fenster wird er invalidiert. Ein schwacher Verweis vom Callback auf den Reader verhindert einen Retain-Zyklus.

## Reaktionsverhalten

Die Glättung passt sich dem Abstand zum bestätigten Ziel an: nahe der Lesezeile bleibt sie sanft (160 ms Zeitkonstante), bei größerem Rückstand reagiert sie schneller (bis 80 ms). Die Geschwindigkeit bleibt auf 2.200 Punkte pro Sekunde begrenzt. Kein Überschwingen oder Vorhersagen ungesprochener Wörter. Bei „Bewegung reduzieren“ wird wie bisher direkt die bestätigte Zielposition verwendet. Nach einer Regieanweisung kann die Bewegung weiterhin die nächste gesprochene Zeile sichtbar machen und dort warten.

Deterministische Simulation bei 120 Schritten pro Sekunde, Zeit bis 95 % eines unveränderten Ziels:

| Entfernung | Vorher | Jetzt |
| --- | ---: | ---: |
| 40 pt | 542 ms | 483 ms |
| 300 pt | 542 ms | 433 ms |
| 600 pt | 558 ms | 458 ms |

Dies misst ausschließlich die Scrollkurve. Es ist keine Messung von Mikrofon-zu-Bildschirm-Latenz oder tatsächlicher Bildschirmdarstellung.

## Weniger wiederholte Arbeit

- Pixelpositionen gehen direkt vom Display-Link bzw. manueller Bewegung an `NSClipView`. Sie lösen keine SwiftUI-Aktualisierung mehr aus.
- Die verstrichene Zeit wird intern genau weitergeführt, aber nur bei einer neuen Sekunde an die Anzeige gemeldet. Der Footer mit Mikrofonpegel und Uhr ist eine eigene View.
- Der Reader beobachtet Skript, Wortmarkierung, Scrollziel und Wiedergabestatus explizit in seiner SwiftUI-View. Er ist nicht mehr auf zufällige Aktualisierungen anderer Anzeigen angewiesen.
- Vollständige Textlayout-Berechnungen erfolgen nur bei Text-, Typografie- oder Breitenänderungen. Reine Höhenänderungen aktualisieren die Scrollgrenzen und das Leseziel ohne erneuten vollständigen Textumbruch.
- Das bestehende Hosting-View und der Reader bleiben bei Größenänderung, Positionierung und Wechsel zwischen Notch und freiem Fenster erhalten.
- Der Modellhelfer verwendet einen vorbereiteten Index mit Originalwörtern, normalisierten Wörtern und Satzgrenzen. Dieser wird bei geändertem Skripttext neu erstellt; die Suche pro Anfrage ist auf die nächsten 24 Wörter begrenzt. Der Index verwendet die bereits vom Wortfolger ermittelten Tokens.

Optimierter lokaler Vergleich mit der vorherigen Kandidatensuche, 2.200 Skriptwörter und 100 Positionen:

| Kandidatenfenster bestimmen | Median | p95 |
| --- | ---: | ---: |
| Vorher: Skript bei jeder Anfrage erneut parsen | 6,44 ms | 7,74 ms |
| Jetzt: vorbereiteten Index verwenden | 0,014 ms | 0,020 ms |

Die einmalige Vorbereitung liegt außerhalb dieser Suchmessung. Fenstertexte und Wortpositionen stimmen in allen 100 verglichenen Fällen überein. Die Zahlen enthalten keine Modellinferenz oder Spracherkennung und belegen keine bestimmte Akkuersparnis.

Reproduzieren:

```sh
swiftc -O -module-cache-path /tmp/macprompter-module-cache \
  MacPrompter/Core/ScriptText.swift MacPrompter/Core/ScriptFollower.swift \
  MacPrompter/Core/LexicalBridge.swift \
  MacPrompter/Services/SemanticRecovery.swift scripts/BenchmarkRendering.swift \
  -o /tmp/macprompter-render-benchmark
/tmp/macprompter-render-benchmark
```

## Scrollen im Sprechtempo (28.10.2026)

Mit der Option „Im Sprechtempo scrollen“ (Einstellungen → Lesen) berechnet `ReaderViewport.continuousVoiceOffset` das Scrollziel im Sprachmodus pro Bild aus einer geschätzten Zeichenposition (`ReadingLead`, ADR-19): eine Glyphenabfrage und zwei Zeilenrechtecke im bereits fertigen Layout, ohne Textlayout und ohne SwiftUI-Durchlauf. Die Bewegung läuft weiter über `ReadingMotion` am Display-Link. Ein Test prüft, dass das Ziel über alle Zeichen eines mehrzeiligen Texts monoton steigt und nirgends eine ganze Zeile springt.

## Markierung, Abdunkeln und Einblenden (10.11.2026)

- **Gelesenes abdunkeln:** Im Modus Stimme bekommt der Text vor dem aktuellen Wort eine temporäre Vordergrundfarbe mit 38 % Deckkraft (`ScriptStyle.spokenAlpha`). Pro Wortwechsel wird nur die Differenz zum vorherigen Stand gesetzt oder entfernt; temporäre Attribute ändern weder Glyphenbreiten noch Layout.
- **Wortkasten:** `WordBoxLayoutManager` (TextKit 1) zeichnet Hintergrund-Markierungen als abgerundete Kästen in Schrifthöhe, ohne den Zeilenabstand darunter. Der Standard füllte das ganze Zeilenfragment; der Kasten ragte in die nächste Zeile, und beim Weiterspringen blieben lila Streifen stehen. Zusätzlich werden die betroffenen Zeilen beim Wechsel vollständig neu gezeichnet.
- **Einblenden:** `OverlayReveal` blendet den Prompter mit einer Feder aus der Notch auf (Maske skaliert von oben, Inhalt blendet ein) und zieht ihn beim Ausblenden in 0,16 s zurück; das Panel wird erst danach entfernt. Mit „Bewegung reduzieren“ nur Überblenden. Die Scrollrad-Überwachung endet sofort beim Ausblenden.
- **Seitenleiste:** Die Konfigurationsleiste blendet ihren Scrollbalken aus. Mit dauerhaft sichtbaren Scrollbalken maß SwiftUI den Inhalt beim Moduswechsel kurz ohne Balken, und die Leiste wurde für einen Moment 17 pt breiter (Regressionstest).

## Prüfung

Neue Tests decken den echten Display-Link mit Start, Hover, Wiederaufnahme und Entfernen aus dem Fenster ab. Weitere Tests prüfen unabhängige Wortmarkierung ohne laufende Uhr, unverändertes Textlayout nach 120 Scroll-/Markierungsupdates, Höhen- gegenüber Breitenänderungen, Erhalt der Reader-Instanz, die schnellere Bewegung ohne Überschwingen sowie vorbereitete Satz-/Cue-Fenster. Bestehende Sprachtests einschließlich der semantischen Rückkehr bleiben Bestandteil der Gesamtsuite.

Noch offen ist eine längere Profiling-Sitzung unter Videokonferenzlast sowie ein visueller Vergleich auf mehreren Monitoren mit unterschiedlichen Bildraten. Diese Änderung optimiert die Verarbeitung; sie verändert keine Spracheinstellungen und benötigt keinen neuen Schalter.
