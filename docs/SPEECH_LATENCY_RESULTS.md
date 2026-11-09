# Sprachführung: Messung vom 24. September 2026

## Korrektur 28. Oktober 2026: Zeit pro Wort und Takt des Erkenners

Die bisherige Kennzahl „Wortende → erkannt“ (in echten Takes 6–7 ms) war falsch. Vorläufige Ergebnisse von `SpeechTranscriber` tragen nur einen Zeitbereich für ihren ganzen Text. Gemessen wurde also das Ende des Teilresultats, nicht das Ende des einzelnen Worts. Auch „Erkennung (Audioende → Ergebnis)“ misst nur das. Richtig gemessen wird jetzt gegen die Wortzeiten der finalen Ergebnisse: wann ein Wort erstmals vorläufig erscheint, verglichen mit seinem eigenen Ende (`WordAppearanceTracker`).

Gleicher Echtzeitaufbau mit den Fixtures und 10-ms-Blöcken, eigenständiges Messprogramm:

| Erkenner | neue Wörter alle | Wort nach seinem Ende, Median / p95 |
| --- | ---: | ---: |
| `SpeechTranscriber` + `.fastResults` (bisher) | ~950 ms | 550–600 ms / 1,6–1,8 s |
| `SpeechTranscriber` ohne `.fastResults` | ~5 s | 2,3–4,3 s / bis 11 s |
| `SpeechTranscriber`, Preset `.progressiveTranscription` | ~950 ms | wie `.fastResults` |
| `DictationTranscriber` (mit und ohne `.frequentFinalization`) | ~245 ms | 390–440 ms / 590–670 ms |

In der XCTest-Suite (`SpeechIntegrationTests`, Ausgabe `WORD_LATENCY`, 2048-Frame-Blöcke): Standard Median 604–609 ms / p95 1.016–1.044 ms, alle 917–928 ms; Diktat mit Skriptvokabular Median 508–517 ms / p95 619–629 ms, alle 277–279 ms.

Echte Takes des Maintainers am 28. Oktober 2026, wörtlich abgelesen:

| Messgröße | Standard | Diktat mit Skriptvokabular |
| --- | ---: | ---: |
| Neue Wörter alle, Median / p95 | 946 / 964 ms | 255 / 503 ms |
| Wortende → erkannt, Median | 632 ms | 436 ms |
| Ereignisse mit Fortschritt | 60 % (210) | 70 % (174) |
| Wort nicht im Skript / noch nicht eindeutig / Einschub | 51 / 12 / 6 | 31 / 16 / 0 |
| Start (davon Mikrofon) | 878 (548) ms | 1.458 (145) ms |

Der p95 von 9.128 ms für „Wortende → erkannt“ beim Diktat war ein Messfehler: Wörter, die vorläufig nie erschienen, zählten mit der Ankunft des finalen Ergebnisses, und die kommt beim Diktat oft erst am Satzende. Sie werden seitdem getrennt gezählt. Der längere Start kam vom Vokabular: `setContext` kostet bei jedem Start ~5,5 ms pro Eintrag (gemessen 25: 242 ms, 50: 304 ms, 100: 527 ms, 200: 1.120 ms, 400: 2.406 ms, 800: ~4 s). Setzt man das Vokabular erst während der laufenden Erkennung, wirkt es nicht auf die bereits laufende Sprache. Seitdem werden höchstens 50 seltene Wörter übergeben (ADR-20); ihre Auswahl über `NLEmbedding` dauert für 2.000 Wörter 42 ms kalt und 2 ms warm.

Der wesentliche Rückstand kommt also vom Takt des Erkenners: Neue Wörter erscheinen nur einmal pro Sekunde in einem Schub. Das Vokabular (keines, nur seltene Wörter, alle Skriptwörter, über 1.500 Einträge) änderte das Tempo nicht; Namen erkannte das Diktiermodell nur mit Vokabular. Synthetische Stimmen; echte Takes stehen aus. Die Sprachdiagnose zeigt beide Werte jetzt für echte Takes.

## Ergänzung 27. Oktober 2026: Schreibweisen angleichen

Ausgangspunkt war eine Stichprobe mit `SpeechTranscriber` (macOS 27.0, Xcode 27.1) und den synthetischen Stimmen Anna und Samantha. Der Erkenner schrieb „drei“, „zwölf“ und „three“ als Wort, „25“, „2026“ und „112“ als Ziffern, „Dr.“ für „Doktor“, englisch „25%“, „email“ und „etc.“, deutsch ausgeschrieben „zum Beispiel“, „das heißt“, „und so weiter“. Keine Mikrofonaufnahme, keine gespeicherten Transkripte.

`scripts/BenchmarkFollowing.swift` speist dafür zwölf DE/EN-Fälle Wort für Wort als wachsende Teilresultate eines Segments ein, so wie sie mit `.fastResults` ankommen. Gezählt wird jedes gehörte Wort, nach dem die Position nicht weiterrückt. Gleiche Toolchain und `-O`, die Ausgangsversion aus `main` (ec98402):

| Messgröße | Vorher | Mit `LexicalBridge` |
| --- | ---: | ---: |
| Wörter ohne Fortschritt (12 Fälle, 70 gehörte Wörter) | 24 | 2 |
| Fälle, die das Satzende erreichen | 11/12 | 12/12 |
| Bestehender Benchmark mit 2.200 Skriptwörtern, Median / p95 (5 Läufe) | 0,163–0,173 / 2,60–2,77 ms | 0,170–0,178 / 2,56–2,77 ms |
| Lokale Rückkehrfälle, Median (5 Läufe) | 0,176–0,180 ms | 0,190–0,196 ms |

Die zwei verbleibenden Stellen sind gewollt: ein gehörtes „Prozent“, wo das Skript „%“ schreibt, und „zum“, bevor „Beispiel“ die Abkürzung „z. B.“ eindeutig macht. Bei 190 Wörtern pro Minute entspricht ein Wort ohne Fortschritt etwa 300 ms Rückstand. Vorher kamen also je Fall meist zwei Wörter, also rund 0,6 s, zusammen.

Grenzen: Die Fälle sind gezielt gewählte Formulierungen, keine Stichprobe natürlicher Takes. Wie oft solche Schreibweisen in echten Skripten vorkommen, ist nicht gemessen. Echte Mikrofonläufe stehen aus; dafür gibt es jetzt die Sprachdiagnose unter Einstellungen → Experimentell.

Nebenbefund: Im bestehenden Fixture `en-aside.aiff` schreibt `SpeechTranscriber` selbst „the battery store“ statt „the batteries store“. Genau diesen Fall deckt die Regel für knapp verfehlte Wörter ab.

## Ergänzung 27. Oktober 2026: Audioblöcke, Start, Erkennungsmodul

Alle Werte stammen aus einem eigenständigen Swift-Programm. Es führt `de-aside.aiff` und `en-aside.aiff` (22,05 kHz) in Echtzeit in Blöcken zu, wie der Mikrofon-Tap. Gemessen wird die Ankunft jedes Ergebnisses abzüglich des gemeldeten Audioendes. Ein Wort am Blockanfang wartet bis zum Blockende, bevor der Erkenner es überhaupt bekommt; diese Wartezeit ist in den Werten enthalten. Je zwei Durchläufe:

| Blockgröße | DE Median / p95 | EN Median / p95 |
| --- | ---: | ---: |
| 42 ms (bisher 2048 Frames bei 48 kHz) | 30–35 / 41–49 ms | 24–30 / 29–36 ms |
| 21 ms | 16–17 / 26–28 ms | 11–23 / 25–27 ms |
| 10 ms (neu) | 9 / 12–13 ms | 10–11 / 12–13 ms |

Zahl und Text der Ergebnisse waren bei allen Blockgrößen gleich. Die App fordert jetzt 10 ms an (`SpeechService.blockSeconds`). Ob ein bestimmtes Mikrofon diese Größe einhält, zeigt die Sprachdiagnose („Audioblock“). Den Pegel im Overlay aktualisiert die App höchstens 30-mal pro Sekunde, mit dem Spitzenwert seit der letzten Aktualisierung.

**Korrektur 28. Oktober 2026:** Mit dem echten Mikrofon des Maintainers zeigte die Diagnose 102,0 ms pro Audioblock. `installTap` ignoriert die gewünschten 10 ms. Der Vorteil aus der Tabelle kam damit in der App nicht an. Im selben Take: Erkennung Median 48 ms / p95 98 ms (passend zur Wartezeit im 100-ms-Block), Wortzuordnung 0,57 / 1,27 ms, Markierung 0,8 / 1,6 ms, Start der Erkennung 752 ms, 256 Ereignisse, davon 40 % mit Fortschritt und 86 revidiert. Seitdem liest die App das Mikrofon über einen `AVAudioSinkNode` in Blöcken der Gerätegröße (`AudioSinkCapture`). Die tatsächliche Blockgröße mit echtem Mikrofon ist noch nicht gemessen.

**Pro Wort** (gleicher Echtzeitaufbau, Zeitbereich des neuesten Worts gegen erstes Erscheinen, nur veränderliche Teilresultate): 102-ms-Blöcke Median 25–30 ms / p95 35–72 ms, 10-ms-Blöcke Median 9–11 ms / p95 13 ms. Das Modell gibt ein Wort also praktisch sofort nach dessen Ende aus. Was danach noch hinterherhängt, ist im Wesentlichen die Dauer des Worts selbst (ADR-19). Synthetische Stimmen; die Diagnose zeigt „Wortende → erkannt“ jetzt für echte Takes.

**Echter Take mit `AVAudioSinkNode`, 28. Oktober 2026** (Mikrofon des Maintainers, beide damals experimentellen Schalter an):

| Messgröße | Tap (27.10.) | Sink-Node (28.10.) |
| --- | ---: | ---: |
| Audioblock | 102,0 ms | 10,6 ms |
| Wortende → erkannt, Median / p95 | – | 6 / 15 ms |
| Erkennung (Audioende → Ergebnis), Median / p95 | 48 / 98 ms | 9 / 47 ms |
| Ergebnisse ab 1 s | 1 | 0 |
| Wortzuordnung, Median / p95 | 0,57 / 1,27 ms | 0,61 / 1,67 ms |
| Markierung angewendet, Median / p95 | 0,8 / 1,6 ms | 0,8 / 32,7 ms |
| Start der Erkennung | 752 ms | 1.970 ms |
| Ereignisse mit Fortschritt | 40 % | 34 % (144 von 256 „nicht zugeordnet“) |

**Dritter Take, wörtlich abgelesen, nur „Im Sprechtempo scrollen“ an:** 181 Ereignisse, 59 % mit Fortschritt. Wortende → erkannt 7 / 13 ms, Erkennung 9 / 35 ms, Wortzuordnung 0,51 / 0,88 ms, Markierung 0,7 / 1,3 ms, Audioblock 10,7 ms, Start 752 ms (davon Mikrofon 392 ms). Ohne Fortschritt: Wort nicht im Skript 41, noch nicht eindeutig 10, Einschub 9, Wiederholung 10, nichts Neues 2, pausiert 2. Damit ist geklärt: Der hohe p95 der Markierung kam von der entfernten Wortvormerkung, die 1.970 ms Start waren ein Kaltstart nach der Installation.

Die 41 Ereignisse „Wort nicht im Skript“ beim wörtlichen Lesen führten zu den halben Wörtern am Ende von Teilresultaten (siehe [SPEECH_FOLLOWING.md](SPEECH_FOLLOWING.md)). `scripts/BenchmarkFollowing.swift` gibt dafür die Zeile `FRAGMENT` aus. Ein nachgestellter Strom mit acht Teilresultaten, die je ein neues vollständiges Wort enthalten, ergibt auf `main` und vor dieser Änderung 4 Hänger, danach 0. Der Strom ist nachgebaut, nicht aus einem echten Take übernommen; wie oft der Erkenner wirklich halbe Wörter liefert, zeigt der nächste echte Take.

Erkennung und Wortende liegen jetzt praktisch bei null. Offen waren nach dem zweiten Take drei Werte. (1) Der p95 der Markierung stieg. Möglicher Grund ist die inzwischen entfernte Wortvormerkung mit zusätzlichen SwiftUI-Durchläufen; mit einem neuen Take prüfen. (2) Der Start dauerte länger. Ob das am Sink-Weg oder an einem ersten Start nach der Installation liegt, zeigt der neue Mikrofonanteil der Startzeit. (3) „Nicht zugeordnet“ ist inzwischen aufgeteilt in „Wort nicht im Skript“, „noch nicht eindeutig“ und „Einschub“.

**Start der Erkennung** (Sprachmodell installiert, ohne Mikrofon): Locale, Modellprüfung, Format und `prepareToAnalyze` dauerten beim ersten Start im Prozess 100–210 ms, danach rund 20 ms. Vorladen würde also höchstens einmal rund 0,2 s vor dem Countdown sparen und wurde nicht umgesetzt. Das Starten des echten Mikrofons ist nicht enthalten; die Diagnose zeigt die gesamte Startzeit des letzten Takes.

**`DictationTranscriber` mit Skriptvokabular** (`AnalysisContext.contextualStrings`) im selben Echtzeitaufbau:

| Modul | Median | p95 | Eigennamen-Satz (DE) |
| --- | ---: | ---: | --- |
| `SpeechTranscriber` (App) | 24–37 ms | 49–55 ms | „Vulkan Gikolu … Mak promter … Speech Analizer“ |
| `SpeechTranscriber` + Vokabular | – | – | unverändert: das Vokabular wird ignoriert |
| `DictationTranscriber` ohne Vokabular | 162–166 ms | 211–248 ms | Vor- und Nachname falsch, „Matoma“ statt „macprompter“, „Speech eine Kolaysa“ |
| `DictationTranscriber` + Vokabular | 185 ms | 354 ms | Vor- und Nachname, „macprompter“, „SpeechAnalyzer“, „Notch-Overlay“ korrekt |

Mit Vokabular erkennt das Diktiermodell Namen und Fachbegriffe, liefert aber jedes Ergebnis rund 130–150 ms später und hat ohne Vokabular mehr Fehler. Entscheidung: [ADR-18](DECISIONS.md). Synthetische Stimmen, ein Satz je Sprache; keine Aussage über natürliche Sprache.


## Ergänzung: lokale Rückkehr bei veränderter Formulierung

Die zweite Optimierung bleibt bei der bestehenden Apple-Spracherkennung und ergänzt nur einen lokalen Wortvergleich mit tolerierten Lücken. Insgesamt 76 Tests geprüft: kompletter Lauf mit 74 Tests, danach die um zwei Grenzfälle ergänzte Rückkehrsuite mit 16 Tests; alles erfolgreich, nichts übersprungen. Release-Build und Signatur erfolgreich geprüft.

Direkter Vergleich mit der vor dieser Änderung gespeicherten Quelldatei, gleiche Toolchain und `-O`:

| Messgröße | Vor dieser Ergänzung | Mit lokaler Rückkehrprüfung |
| --- | ---: | ---: |
| Fünf gezielt problematische DE/EN-Fortsetzungen, je 30 Wiederholungen | 0/150 Anschlüsse | 150/150 Anschlüsse |
| Zuordnung dieser Ereignisse, Median | 0,176 ms | 0,187 ms |
| Zuordnung dieser Ereignisse, p95 | 0,218 ms | 0,228 ms |
| Zuordnung dieser Ereignisse, Maximum | 0,295 ms | 0,336 ms |
| Bestehender Benchmark mit 2.200 Skriptwörtern, p95 | 3,35 ms | 3,27 ms |

Der zusätzliche Aufwand war hier gering. Kleine Unterschiede im langen Benchmark sind Messschwankungen, kein Nachweis einer generellen Beschleunigung. Der Nutzen ist, dass passende Schlüsselwörter trotz leicht veränderter Formulierung jetzt ausreichen.

Die fünf Fälle umfassen veränderte englische und deutsche Satzanfänge, ersetzte Wörter, einen nachgeschobenen Einschub sowie anderen Wortschatz aus Kochen und Reisen. Die Wiederholungen messen Laufzeit; sie sind keine 150 unterschiedlichen natürlichen Sprechproben. Die vollständigen Schutztests prüfen auch, dass einzelne, vertauschte, mehrdeutige oder verstreute Wörter keinen solchen Anschluss auslösen.

`scripts/BenchmarkFollowing.swift` gibt zusätzlich eine Zeile `FLEXIBLE` mit den neuen Fällen aus. Der unten dokumentierte Aufruf bleibt gültig. Unabhängig gemessene menschliche Wortende-zu-Bildschirm-Latenz ist weiterhin offen.

## Ergebnis der ersten Optimierungsrunde

60 XCTest-Tests bestanden, keine übersprungenen Tests. Darunter vier tatsächliche lokale DE/EN-Sprachintegrationstests, zwei davon mit in Echtzeit zugeführtem Audio. Release-Build und Signatur separat geprüft.

Die wesentliche Verbesserung ist die benötigte Evidenz am bisherigen Anschluss: Ein eindeutiges erwartetes Wort oder eine kurze lokale Rückkehrphrase kann sofort folgen. Zuvor mussten selbst solche Fälle nach einem Einschub vier passende Wörter sammeln. Die Wortanzeige spielt gebündelte Ergebnisse nicht mehr mit 70 ms Abstand nach, sondern markiert unmittelbar das neueste bestätigte Wort.

## Zuordnungsbenchmark

Mac mit Apple Silicon, macOS 27.0, Xcode 26.2, Swift-Optimierung `-O`. 2.200 Skriptwörter, 270 Ereignisse mit normaler Fortsetzung, Einschub und globaler Suche in einem absichtlich repetitiven Skript. Skriptinitialisierung außerhalb der Zeitmessung; Parsing jedes Teilresultats innerhalb der Messung.

| Messgröße | Vorherige Zuordnungslogik | Neue Zuordnungslogik |
| --- | ---: | ---: |
| Median pro Ereignis | 0,82 ms | 0,17 ms |
| p95 pro Ereignis | 1,67 ms | 3,14 ms |
| Langsamstes Ereignis | 2,38 ms | 5,46 ms |
| Vier gezielte DE/EN-Rückkehrfälle nach 1–2 passenden Wörtern | 0/4 | 4/4 |

Die Ausgangsversion wurde für den Vergleich aus der vorherigen Logik rekonstruiert und mit derselben Toolchain kompiliert. Die Fälle sind im Benchmarkskript enthalten. Die aufwendigere globale Bewertung kostet etwas mehr als vorher; der schnelle lokale Pfad ist günstiger. Beide bleiben hier unter dem Ziel von 10 ms bei p95. Der Effekt auf das Sprechgefühl entsteht hauptsächlich durch weniger Warten auf zusätzliche Wörter, nicht durch das Einsparen einer Millisekunde Rechenzeit.

Aktuelle Version reproduzieren:

```sh
swiftc -O -module-cache-path /tmp/macprompter-swift-cache \
  MacPrompter/Core/ScriptText.swift MacPrompter/Core/ScriptFollower.swift \
  MacPrompter/Core/LexicalBridge.swift \
  scripts/BenchmarkFollowing.swift -o /tmp/macprompter-following-benchmark
/tmp/macprompter-following-benchmark
```

Der Debug-XCTest-Benchmark ist absichtlich nicht optimiert und lag bei etwa 18,5 ms p95. Diesen Wert nicht mit dem ausgelieferten Release-Code verwechseln. Die Testgrenze ist großzügiger, damit langsamere Testmaschinen nicht allein aufgrund ihrer Hardware fehlschlagen.

## Wortmarkierung

Ein Reader-/Session-Test liefert fünf erkannte Wörter in einem Ereignis. Die Markierung muss ohne Timer-Schritt direkt auf dem fünften Wort stehen. Gemessen: rund **0,30 ms** vom Ereigniseingang bis zum Anwenden der temporären Textattribute im direkt aktualisierten Test-Reader.

Das ist kein Nachweis der physischen Displaylatenz: SwiftUI-Scheduling, WindowServer und Bildschirm-Scanout sind in diesem direkt angestoßenen Reader-Test nicht enthalten. Der Test belegt die Entfernung der bisherigen Warteschlange und prüft die tatsächlichen Textattribute.

## Zeitgetreue Audiointegration

Synthetische, lokal erzeugte Stimmen: Anna (Deutsch) und Samantha (Englisch), 190 Wörter/Minute, eine eingeplante Pause von 700 ms und ein freier Einschub. Der Test liefert PCM-Blöcke entsprechend ihrer tatsächlichen Audiodauer an denselben Konverter und SpeechAnalyzer wie die App. Eine Sekunde zusätzliche Stille am Dateiende simuliert das weiterlaufende Mikrofon.

Beide Tests erreichen die erwartete Skriptstelle **vor dem Finalisieren des Audiostreams**. Sie benötigen also weder ein manuelles Stoppen noch ein abschließendes Erkennungsergebnis zum Wiedereinstieg. Die gesamte Testsuite benötigte rund 21 Sekunden.

| Sprache | Nicht revidierte Ergebnisse | Geschätzter Abstand zum gemeldeten Audioende, Median / p95 | Tracker p95 (Debug) |
| --- | ---: | ---: | ---: |
| Englisch | 24 | 26,9 / 41,4 ms | 1,16 ms |
| Deutsch | 25 | 34,9 / 52,4 ms | 1,12 ms |

**Die kleinen Audio-Abstände sind keine unabhängige Wortende-zu-Anzeige-Latenz.** Sie verwenden die vom Erkenner gemeldeten Abschnittsenden; diese müssen nicht exakt den akustischen Wortenden entsprechen. Revidierte Ergebnisse werden gesondert erfasst. Die Zahlen dürfen nicht als Zusage „Spracherkennung in 40 ms“ verwendet werden.

Fixturetexte:

- Deutsch: „Heute untersuchen wir. [700 ms Stille] Das erinnert mich übrigens an eine Geschichte aus meinem letzten Urlaub. Solarmodule und moderne Speicher liefern nachhaltige Energie.“
- Englisch: „Welcome everyone. [700 ms Stille] Let me tell you a quick story about my recent vacation. The batteries store clean energy for tomorrow.“

Die jeweils mittlere Aussage ist nicht im Testskript enthalten. Die Audiodateien liegen als `de-aside.aiff` und `en-aside.aiff` unter `MacPrompterTests/Fixtures`. Es wurde keine persönliche Mikrofonaufnahme erzeugt oder gespeichert.

## Was damit noch nicht belegt ist

- Eine garantierte Gesamtreaktion von 150–300 ms bei natürlich gesprochenem Audio. Dafür fehlen unabhängig markierte menschliche Wortenden und eine zeitlich zuordenbare Messung der real sichtbaren Ausgabe.
- Robustheit für jeden Akzent, jedes Mikrofon oder jede freie Paraphrase.
- CPU-/Energieverbrauch über lange Takes.
- Perfekte Unterscheidung zwischen einem gesprochenen Anschlusswort und demselben Wort innerhalb einer freien Anekdote.

Die obigen Messungen betreffen die normale Wortverfolgung. Seit dem 24. September 2026 gibt es zusätzlich eine standardmäßig ausgeschaltete Apple-Modellhilfe für Umformulierungen. Deren getrennte Messwerte und Grenzen stehen in [SEMANTIC_RECOVERY.md](SEMANTIC_RECOVERY.md).
