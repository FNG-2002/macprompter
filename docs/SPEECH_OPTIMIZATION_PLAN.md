# Sprachführung: nächste Optimierung

Festgehalten am 24. September 2026 für die nächste Arbeitssitzung. Die erste Umsetzung ist am 24. September 2026 erfolgt; siehe Status unten.

## Ziel und wichtigste Vorgabe

Die Sprachführung soll bei Redepausen, Füllwörtern und spontan eingefügten Nebensätzen schnell wieder anschließen. Auch nach einer längeren Anekdote soll der bisherige Anschluss erhalten bleiben.

**Geschwindigkeit hat Vorrang: Eine Sekunde gefühlte Verzögerung ist für den Nutzer bereits zu lang.** Keine absichtliche Wartefrist von einer Sekunde, kein Warten auf abgeschlossene Sätze und keine zusätzliche Modellabfrage im normalen Wort-für-Wort-Pfad.

Die App darf Schnelligkeit nicht durch erfundene Wortpositionen erkaufen. Bei mehrdeutigem Text bleibt sie stehen, bis genügend Information vorliegt. Dieses notwendige Warten ist von vermeidbarer Verarbeitungslatenz zu unterscheiden.

## Ausgangslage

- Apple Speech liefert bereits schnelle, veränderliche Teilresultate lokal auf dem Mac.
- Der aktuelle Tracker betrachtet bis zu zwölf gehörte Wörter. Nach vier nicht zugeordneten Wörtern verlangt er für den Wiedereinstieg mindestens vier passende Wörter, darunter zwei aussagekräftige.
- Dadurch werden auch lokale Fortsetzungen nach kurzen Einschüben unnötig streng behandelt.
- Stille allein setzt den Tracker nicht in den Suchmodus. Verzögerungen nach reinen Sprechpausen müssen separat auf Erkennung, Segmentwechsel und Zuordnung untersucht werden.
- Die Wortanzeige kann bestätigte Wörter in einer kurzen Folge mit 70 ms Abstand abspielen. Auch dieser zusätzliche Rückstand gehört in die Messung.
- Die bestehenden 39 Tests sichern wichtige Fälle ab, reichen aber für natürliche, spontane Takes noch nicht aus.

## 1. Zuerst Latenz messbar machen

Erfassen: Ende des gesprochenen Wortes im Audio → Eingang des zugehörigen Teilresultats → Entscheidung des Trackers → sichtbare Markierung. Audiozeit und monotone Laufzeit müssen dafür auf dieselbe Zeitbasis bezogen werden. Revidierte Teilresultate gesondert behandeln.

Für reproduzierbare Testaufnahmen die tatsächlichen Wortenden markieren; die vom Erkenner gelieferten Zeitstempel allein sind kein unabhängiger Nachweis der Latenz. Die sichtbare Ausgabe stichprobenartig mit einer zeitlich zuordenbaren Aufnahme prüfen.

Vorläufige Entwicklungsziele, keine bereits gemessenen Zusagen:

| Messgröße | Ziel |
| --- | --- |
| Lokale Zuordnung nach Eingang eines Teilresultats | p95 unter 10 ms auf dem Test-Mac |
| Eingang eines eindeutig zuordenbaren Teilresultats bis zur Markierung | p95 unter 50 ms; kein aufgestautes Abspielen alter Markierungen |
| Wortende bis zur Markierung beim normalen Lesen / eindeutigen lokalen Fortsetzen | möglichst 150–300 ms; p95 unter 400 ms als anfängliches Prüfziel |
| Fälle mit mindestens 1 s Verzögerung | einzeln auswerten: Erkennung, Mehrdeutigkeit, Tracker oder Darstellung |

Zusätzlich Fehlersprünge, Wiedereinstiegsdauer, CPU-Last und Speicherverbrauch messen. Nicht nur Durchschnittswerte berichten. Falls bereits Apple Speech das Zeitbudget verbraucht, kann ein schnellerer Tracker das nicht kompensieren; dann zuerst den Erkennungspfad untersuchen.

Messungen lokal und möglichst nur mit Zeit-/Positionsdaten durchführen. Keine automatische Speicherung persönlicher Mikrofonaufnahmen oder vollständiger Transkripte. Für Wiederholbarkeit eigene Testfixtures verwenden.

## 2. Priorität: lokale Fortsetzung und Einschübe

Die bestehende Sequenzzuordnung zunächst um einen kleinen, begrenzten Satz möglicher Lesepfade erweitern. Als Ausgangspunkt genügen etwa 4–8 Kandidaten; die Größe anhand der Messungen festlegen. Kein großes Modell und kein Training nötig.

- **Anschluss behalten:** Ein freier Einschub hält die bisherige Skriptposition als wahrscheinlichen Rückkehrpunkt fest, auch wenn die gesprochenen Wörter aus dem kurzen Textfenster herausfallen.
- **Lokal schnell fortsetzen:** Das erwartete eindeutige nächste Wort kann unmittelbar fortsetzen. Bei kleinen Lücken oder Mehrdeutigkeit weitere passende Wörter abwarten. Ein bis zwei Wörter sind eine Möglichkeit bei ausreichender Evidenz, keine pauschale Freigabe.
- **Entfernte Sprünge streng prüfen:** Rücksprünge und Wechsel in andere Absätze benötigen deutlich mehr Evidenz als das Fortsetzen am gespeicherten Anschluss.
- **Einschübe günstiger bewerten als übersprungene Skriptwörter:** Ein zusammenhängender Nebensatz soll die bisherige Zuordnung nicht mit jedem zusätzlichen Wort weiter zerstören. Eine Sequenzausrichtung mit unterschiedlichen Kosten für Beginn und Fortsetzung eines Einschubs ist ein realistischer erster Ansatz.
- **Füllwörter kontextabhängig behandeln:** „Ähm“/„äh“ schwach gewichten. „Also“, „genau“, „eigentlich“ und englische Entsprechungen nicht global löschen; sie können regulärer Skripttext sein.
- **Stille ist keine Abweichung:** Position und Vertrauen über Sprechpausen erhalten. Ein neuer Erkennungsabschnitt darf keinen unnötigen vollständigen Suchlauf erzwingen.
- **Korrekturen und Wiederholungen absichern:** Veränderliche Teilresultate dürfen weder doppelt zählen noch mit inzwischen korrigierter Evidenz einen Sprung auslösen.

Das entspricht einem schlanken probabilistischen Tracker bzw. einer begrenzten Suche über mögliche Lesepfade. Ein formales Hidden-Markov-Modell ist eine mögliche Umsetzung, aber kein Selbstzweck. Zuerst nachvollziehbare Scores und Übergänge verwenden; unkalibrierte Scores nicht als echte Wahrscheinlichkeiten ausgeben.

## 3. Darstellung ohne zusätzlichen Rückstand

Wortmarkierung und Scrollbewegung getrennt behandeln. Bei mehreren neu erkannten Wörtern darf die Markierung schnell zur aktuellen bestätigten Position aufschließen, statt überholte Wörter lange nachzuspielen. Das Scrollziel weiterhin weich anfahren, auch kurz nach Ende der Sprache, bis die nächste Sprechzeile sichtbar ist.

Hover, manuelle Pause und manuelles Navigieren behalten Vorrang. Nach deren Ende keine während der Pause gesprochenen Wörter nachholen.

## 4. Optional: semantisches Modell nur bei nachgewiesenem Mehrwert

Erst prüfen, wenn die Punkte 1–3 umgesetzt und gemessen sind. Für Füllwörter und lokale Nebensätze ist ein zusätzliches neuronales Modell voraussichtlich nicht nötig. Sein möglicher Nutzen liegt im Wiederfinden einer umformulierten Passage.

- Skriptabschnitte einmal vorberechnen und bei Änderungen gezielt aktualisieren.
- Native Satz-Embeddings von Apple als erste Vergleichsbasis prüfen; Verfügbarkeit und Qualität für Deutsch und Englisch separat testen.
- Nur falls erforderlich ein mehrsprachiges Sentence-Embedding-Modell wie `paraphrase-multilingual-MiniLM-L12-v2` evaluieren. Es ist ein Kandidat, keine bereits bestätigte schnelle Core-ML-Lösung.
- Nur bei unsicherem Anschluss mit ausreichend neuem Text arbeiten; niemals jedes Teilresultat ungefiltert an ein Modell schicken.
- Asynchron rechnen, höchstens eine aktuelle Anfrage behalten und veraltete Ergebnisse verwerfen. Der normale Tracker wartet nicht darauf.
- Semantik schlägt mögliche Abschnitte vor. Wortübereinstimmungen, bisherige Position und Abstand zum zweitbesten Kandidaten entscheiden über einen tatsächlichen Wechsel.
- Eine thematisch ähnliche Anekdote darf keinen Sprung auslösen. Semantische Ähnlichkeit liefert keine zuverlässige genaue Wortposition.

Aufnahme nur bei messbar schnellerem oder zuverlässigerem Wiedereinstieg ohne relevante Zunahme falscher Sprünge und ohne Beeinträchtigung des normalen Folgens. Startzeit, Modellgröße und Ressourcenbedarf mitmessen. Keine konkreten Geschwindigkeitsversprechen vor dem Benchmark.

## Vorerst zurückstellen

- Generative LLM-Aufrufe für die laufende Positionsentscheidung.
- Cloud-Erkennung oder Netzwerkzugriffe während des Takes.
- Wechsel zu Whisper ohne Nachweis, dass die jetzige Erkennung der Engpass ist.
- Eigenes Modelltraining, bevor ein ausreichend vielfältiger, gekennzeichneter Testsatz existiert.
- Pauschales Absenken aller Schwellen: Das beschleunigt auch falsche Sprünge.
- Vorhersage und Markierung noch nicht gesprochener Wörter.

## Realistische Abnahmefälle

Deutsch und Englisch, sowohl mit schrittweisen/revidierten Transkripten als auch mit natürlich eingesprochenen Audiofixtures:

1. Pause mitten im Satz, anschließend exakte Fortsetzung.
2. Einzelne und mehrere Füllwörter zwischen Skriptwörtern.
3. Kurzer Nebensatz und längerer freier Einschub; danach Fortsetzung am bisherigen Anschluss.
4. Längere Anekdote mit zufällig vorkommenden Skriptwörtern; kein falscher Sprung.
5. Wiederholung, Selbstkorrektur, ausgelassenes Wort und korrigiertes Erkennungsresultat.
6. Ähnliche Sätze an mehreren Stellen sowie echte Rückkehr zu einer früheren Passage.
7. Kurze Schlussphrase nach einem Einschub.
8. Regieanweisungen, Hover, manuelle Pause und manuelles Verschieben während unsicherer Zuordnung.

Erst Baseline aufnehmen, dann jede Änderung mit denselben Fällen vergleichen. Zusätzlich unbenutzte Varianten zurückhalten, damit die Lösung nicht nur auf die bekannten Beispiele abgestimmt wird. Bestehende Schutztests weiter bestehen lassen.

## Einstieg in die nächste Sitzung

1. `Core/ScriptFollower.swift`, `Core/Session.swift` und `Services/SpeechService.swift` anhand der Messpunkte prüfen.
2. Kleine DE/EN-Szenariosammlung und Baseline erstellen.
3. Anschluss über Einschübe erhalten und lokale Fortsetzung beschleunigen.
4. Latenz und Fehlersprünge vergleichen; Anzeige-Rückstand beseitigen.
5. Erst danach entscheiden, ob semantische Hilfe überhaupt nötig ist.

## Referenzen

- [Aktuell implementierte Sprachführung](SPEECH_FOLLOWING.md)
- [Apple: Satz-Embeddings und optionale Verfügbarkeit](https://developer.apple.com/documentation/naturallanguage/nlembedding/sentenceembedding%28for%3A%29)
- [Sentence Transformers: mehrsprachige Modelle](https://www.sbert.net/examples/sentence_transformer/training/multilingual/README.html)
- [Apple: Core-ML-Optimierung und hardwareabhängige Performance](https://apple.github.io/coremltools/docs-guides/source/opt-overview.html)

## Umsetzungsstand 24. September 2026

- Implementiert: lokaler Anschluss mit bis zu sechs Kandidaten, dauerhafter Anker für Einschübe, kontextabhängige Füllwortbehandlung und affine Lückenkosten; strenge Regeln für entfernte Sprünge bleiben bestehen. Gewichtete Sequenzsuche, kein trainiertes Wahrscheinlichkeitsmodell.
- Implementiert: unmittelbare Markierung des neuesten bestätigten Worts ohne Nachspiel-Warteschlange.
- Implementiert: begrenzte lokale Latenzdiagnose ohne Transkript-/Audiospeicherung; Tests für verzögerte Audio-Callbacks und Anzeigeanwendung.
- Geprüft: DE/EN-Transkript-Szenarien, unveränderte Schutzfälle, anderer Wortschatz, lange Skripte und in Echtzeit zugeführte synthetische DE/EN-Audios mit Pause und Einschub.
- Bewusst nicht ergänzt: Embedding-Modell. Die untersuchten lokalen Rückkehrfälle funktionieren ohne weitere Modelllatenz oder Modellinstallation. Freie Paraphrasen bleiben ein eigener späterer Evaluationsfall.
- Noch offen: natürliche menschliche Beispieltakes mit unabhängig markierten Wortenden, tatsächliche Displaylatenz und Energieverbrauch. Die 150–300 ms bleiben ein Ziel, keine bestätigte Ende-zu-Ende-Garantie.
- Messwerte und reproduzierbarer Benchmark: [SPEECH_LATENCY_RESULTS.md](SPEECH_LATENCY_RESULTS.md).

## Zweiter Schritt: tolerantere lokale Rückkehr

Auf Nutzerwunsch umgesetzt: ein zusätzlicher lokaler Pfad für Einschub plus leicht veränderte Fortsetzung. Fenster von 16 Skriptwörtern, zwei bis drei geordnete eindeutige Schlüsselwörter, kurze Einfügungen/Auslassungen und bis zu drei nachgeschobene Wörter. Die bisherige schnelle Verfolgung und strengere globale Suche bleiben vorrangig.

**Dauerhafte Produktvorgabe:** Alles muss on-device bleiben. Für eine mögliche spätere semantische Erweiterung native Apple-Modelle bzw. Apple-Frameworks bevorzugen. In diesem Schritt keine Embedding-Modelle, fremden Modellpakete oder Cloud-Dienste ergänzt. Zunächst die Verbesserung im persönlichen Einsatz beurteilen.

16 neue Rückkehr-/Schutztests bestanden; zusammen mit der bisherigen Suite sind 76 Tests geprüft. Messvergleich im [Latenzbericht](SPEECH_LATENCY_RESULTS.md).
