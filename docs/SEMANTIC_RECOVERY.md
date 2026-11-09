# Apple-Modellhilfe für Umformulierungen

Seit 28. Oktober 2026 im Modus Stimme immer aktiv, ohne Schalter (ADR-22). Wie oft sie eingreift, zeigt Einstellungen → Diagnose → „Rückkehr per Satzmodell“. Bis dahin war sie ein experimenteller Schalter (Stand der folgenden Abschnitte: 24. September und 5. Oktober 2026).

Die App verwendet Apples `NaturalLanguage.NLEmbedding.sentenceEmbedding` für Deutsch und Englisch. Das ist ein kleines natives Satzmodell zur Bedeutungsähnlichkeit, kein generatives Foundation-Models-/Apple-Intelligence-LLM. Die Modelle sind auf diesem Mac lokal verfügbar. Fehlt ein Modell auf einem anderen Mac, bleibt die bisherige Wortverfolgung aktiv. Die App lädt für diesen Helfer keine Modelle nach und verwendet keinen Cloud-Fallback.

## Ablauf

1. Die bestehende Wortausrichtung läuft zuerst und ohne Warten auf das Modell.
2. Nur bei fehlendem Anschluss und mindestens vier noch nicht verarbeiteten gesprochenen Wörtern wird ein semantischer Vergleich vorbereitet.
3. Bis zu vier nahe Skriptpassagen innerhalb der nächsten 24 Wörter werden mit höchstens zwölf gesprochenen Wörtern verglichen. Satzgrenzen und überlappende Fenster erlauben kleinere Änderungen.
4. Eine Passage muss mindestens 0,74 Kosinusähnlichkeit erreichen und zu einer anderen möglichen Ankerposition mindestens 0,10 Abstand haben. Diese Schwellen sind konservative Heuristiken, keine Wahrscheinlichkeiten.
5. Zusätzlich muss in den letzten vier gesprochenen Wörtern ein aussagekräftiges Skriptwort vorkommen, das in den Kandidaten genau eine Skriptposition bezeichnet. Markiert wird dieses Wort. Ohne ein solches Wort erfolgt kein Sprung. Ein einfacher Negationsvergleich blockiert offensichtliche Widersprüche, versteht aber keine komplexen Verneinungen.

Ein Beispiel, das der bisherige Tracker in der Testfixture nicht übernimmt: Skript „Next we compare the costs and examine the results.“ → gesprochen „Now let's verify our results“. Der Helfer kann hier bis „results“ anschließen.

## Reaktionszeit und Ressourcen

- Modelle und Vektorzugriffe sind in einem eigenen Actor serialisiert; `NLEmbedding` wird nicht zwischen Threads geteilt.
- Höchstens eine laufende Berechnung plus eine ersetzbare neueste Anfrage. Es entsteht keine Warteschlange alter Teilergebnisse.
- 64 Skriptvektoren bleiben im begrenzten Arbeitsspeicher-Cache. Gesprochene Texte oder Vektoren werden nicht dauerhaft gespeichert.
- Beim Öffnen des Prompters mit aktivierter Option werden die ersten Kandidaten vorbereitet.
- Pause, Hover, Ausblenden, Positionswechsel, Ausschalten und veränderte Transkripte entwerten laufende Ergebnisse. Identische Wortfolgen desselben Audioabschnitts erhalten die laufende oder wartende Anfrage, ohne deren Frist zu verlängern. Ergebnisse älter als 250 ms bewegen den Prompter nicht mehr.

Lokaler optimierter Benchmark: je Sprache 100 Aufrufe, abwechselnd eine passende Umformulierung und eine fremde Aussage mit demselben Ankerwort; vorbereitete Skriptvektoren. Deutsch: Median **3,29 ms**, p95 **3,99 ms**. Englisch: Median **2,83 ms**, p95 **3,25 ms**. Initiales Laden einschließlich erster Skriptvektoren: etwa **57 ms DE / 16 ms EN**, außerhalb der UI-Ausführung. Pro Sprache wurden alle 50 Wiederholungen der passenden und alle 50 Wiederholungen der unpassenden Fixture korrekt behandelt.

Diese Wiederholungen messen Laufzeit und Stabilität, keine Erkennungsquote im Alltag. Die Werte enthalten weder SpeechAnalyzer noch Mikrofon-, SwiftUI- oder Bildschirmverzögerung. Eine insgesamt garantierte Reaktionszeit lässt sich daraus nicht ableiten. Freie Umschreibungen ohne gemeinsame Wörter, große Sprünge und sehr ähnliche Themen können weiterhin ausbleiben oder verwechselt werden; deshalb bleibt die Funktion experimentell und optional.

Reproduzieren:

```sh
swiftc -O -module-cache-path /tmp/macprompter-module-cache \
  MacPrompter/Core/ScriptText.swift MacPrompter/Core/ScriptFollower.swift \
  MacPrompter/Core/LexicalBridge.swift \
  MacPrompter/Services/SemanticRecovery.swift scripts/BenchmarkSemanticRecovery.swift \
  -o /tmp/macprompter-semantic-benchmark
/tmp/macprompter-semantic-benchmark
```

Automatisierte Tests prüfen echte lokale DE-/EN-Modelle, eindeutige Anker, Negationen, ausgeschlossene Cues, ignorierte Sprache während Hover, deaktivierte und fehlende Modelle, persistierte Einstellungen, Positionsschutz bei verspäteten Ergebnissen, Priorität neuer Worttreffer, die 250-ms-Grenze und die begrenzte Warteschlange. Echte Modelltests werden bei fehlendem Systemmodell übersprungen.

Referenz: [Apple NLEmbedding](https://developer.apple.com/documentation/naturallanguage/nlembedding).

## Verbesserung vom 5. Oktober 2026

Scheitert der Vergleich des vollständigen Kontexts unterhalb der bisherigen Ähnlichkeitsschwelle, prüft der Helfer bei mindestens acht Kontextwörtern zusätzlich die letzten fünf Wörter. So kann der Beginn des Kontexts noch eine Anekdote enthalten, während sein Ende bereits zum Skript zurückführt. Ein erfolgreicher oder bereits ausreichend ähnlicher, aber mehrdeutiger vollständiger Vergleich wird nicht durch einen ausgesuchten Ausschnitt ersetzt.

Die zusätzliche Variante ist auf eine weitere Modellabfrage beschränkt, verwendet dieselben vorbereiteten Skriptvektoren und behält konkurrierende Anker aus dem vollständigen Vergleich bei. Sie verlangt mindestens zwei aussagekräftige Wörter sowie einen eindeutigen Skriptanker in den letzten zwei Wörtern. Verneinungen im abgeschnittenen Anfang verhindern die kurze Variante; sie darf einen Widerspruch nicht einfach abschneiden. Das ist weiterhin eine konservative Heuristik, kein vollständiges Sprachverständnis.

Identische Transkripte werden anhand derselben Audioabschnitts-ID und derselben normalisierten Wortfolge erkannt. Reine Groß-/Kleinschreibung und Satzzeichenänderungen lösen keine neue Modellabfrage aus und verwerfen keine laufende oder wartende Antwort. Ein neuer Audioabschnitt mit denselben Wörtern gilt dagegen als neue Sprache. Echte Korrekturen, neue Wörter und die bestehenden Pausensperren entwerten alte Antworten weiterhin. Duplikate verlängern die 250-ms-Frist nicht.

Vergleich mit deaktivierter zusätzlicher Endprüfung, gleicher optimierter Benchmark und vorbereiteten Skriptvektoren:

| Gezielt problematischer Anschluss nach Einschub | Vorher | Nachher | Modellberechnung p95 vorher → nachher |
| --- | --- | --- | --- |
| Deutsch | 0/50 Wiederholungen | 50/50 Wiederholungen | 5,40 → 8,65 ms |
| Englisch | 0/50 Wiederholungen | 50/50 Wiederholungen | 5,08 → 8,22 ms |

Pro Sprache ist das jeweils **eine passende Formulierung**, 50-mal wiederholt, plus 50 Wiederholungen einer unpassenden Aussage. Die unpassenden Aussagen wurden vorher und nachher abgewiesen. Die Wiederholungen messen Laufzeit und Stabilität, keine allgemeine Erkennungsquote. Die kurzen vorhandenen Vergleichsfälle blieben erfolgreich; deren p95 lag im selben Lauf bei 3,68 ms DE / 3,11 ms EN. Die zusätzliche Prüfung kostet im betroffenen Pfad einige Millisekunden, kann dafür das Warten auf weitere passende Wörter vermeiden. Mikrofon- und Spracherkennungszeit sind nicht enthalten.

Die Tests prüfen den vollständigen Anschlussweg durch die Sitzung in beiden Sprachen, fremde Aussagen, abgeschnittene Verneinungen, identische laufende und wartende Resultate, Korrekturen, neue Audioabschnitte und die unveränderte Frist für alte Antworten.

Die Sitzung verwendet seit dem 5. Oktober 2026 einen vorbereiteten Skriptindex für die Kandidatensuche. Der Vergleich der Suchkosten steht in [RENDERING_OPTIMIZATION.md](RENDERING_OPTIMIZATION.md). Die oben gemessene Modellinferenz bleibt eine getrennte Messgröße.
