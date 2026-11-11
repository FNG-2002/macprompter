# Sprachführung

## Verhalten

Das aktuell erkannte Skriptwort erhält weiße Schrift und eine schwache Hintergrundmarkierung. Der restliche Sprechtext bleibt leicht grau; Regieanweisungen bleiben grau und kursiv. Die Schriftbreite ändert sich durch die Markierung nicht. Wenn der Erkenner mehrere Wörter gleichzeitig liefert, zeigt die App sofort das neueste bestätigte Wort. Es gibt keine Warteschlange und keine künstliche Verzögerung pro Wort. Beim Wiedereinstieg springt die Markierung direkt zur wiedergefundenen Stelle.

Der sichtbare Text bewegt sich unabhängig von den Erkennungsereignissen. Jede bestätigte Position liefert ein Scrollziel, das weich angefahren wird. Dabei bleibt die nächste gesprochene Zeile oberhalb des unteren Verlaufs sichtbar. Das überbrückt Leerzeilen und Regieanweisungen, ohne Speech-Ereignisse während der Pause zu benötigen. Es gibt kein selbstständiges Weiterscrollen über dieses Ziel hinaus. Manuelle Pause und Hover unterbrechen die Bewegung sofort und verwerfen noch wartende Markierungen.

## Ausrichtung

1. Normalisierte Wörter mit originalen UTF-16-Positionen; Klammer-Cues zählen nicht als gesprochene Wörter. Umlaute, Großschreibung und Interpunktion beeinflussen den Vergleich nicht.
2. Die letzten bis zu zwölf gehörten Wörter werden über Segmentgrenzen hinweg zusammen betrachtet. Veränderliche Teilresultate ersetzen ihren alten Text, statt als neue Äußerung angehängt zu werden. Eine bereits konsumierte Wortposition schützt vor erneutem Fortschritt durch Korrekturen.
3. Zuerst werden höchstens sechs folgende Wortpositionen als lokale Anschlüsse geprüft. Die zuletzt bestätigte Position bleibt über beliebig lange Einschübe und Stille erhalten. Ein eindeutiges, aussagekräftiges nächstes Wort kann auch nach einer Abschweifung sofort fortsetzen. Bei allgemeinen Wörtern genügt eine zusammenhängende Folge mit einem aussagekräftigen Wort. Ein einzelnes ausgelassenes Skriptwort braucht zwei aussagekräftige Nachbarwörter. Bereits verbrauchter Kontext zählt nicht als neue Evidenz.
4. Die Zuordnung unterscheidet eingefügte Sprache von ausgelassenem Skripttext. Ein Einschub kostet beim Beginn mehr als bei seiner Fortsetzung (affine Lückenbewertung); ausgewählte Füllwörter kosten weniger. Nur eine kurze Füllwortfolge darf die lokale Rückkehrphrase unterbrechen. Verstreute Treffer in einer Anekdote ergeben keinen schnellen lokalen Anschluss. Wörter wie „also“ oder „actually“ bleiben erhalten, wenn sie selbst im Skript stehen. Reine Zögerlaute am Ende eines Erkennungsblocks blockieren einen schon passenden Wortabschluss nicht.
5. Ohne lokalen Anschluss betrachtet die globale Suche höchstens 240 mögliche Endpositionen. Ein sortierter Wortindex mit binärer Suche vermeidet das wiederholte Sortieren langer Skripte. Die Sequenzausrichtung endet auf dem letzten gehörten Wort (gegebenenfalls vor abschließenden Zögerlauten).
6. Nach vier nicht zugeordneten Wörtern zeigt die Sitzung einen freien Einschub an. Der lokale Anschluss bleibt verfügbar. Für einen sonstigen Wiedereinstieg, Rücksprünge oder Sprünge über mehr als 24 Wörter gelten weiter mindestens vier unverbrauchte Übereinstimmungen, zwei aussagekräftige Wörter, 78 % Übereinstimmung und zwei passende Schlusswörter. Eine eindeutige kurze Schlussphrase kann ebenfalls wieder einsteigen.
7. Gleich gute entfernte Phrasen werden nicht erraten. Erst unterscheidende Folgewörter erlauben den Sprung. Die lokale Fortsetzung hat einen starken Vorrang; das ist eine bewusste Annahme über normales Lesen.

### Folienwechsel von Hand

Ein Folienwechsel per Taste, Klicker oder iPhone setzt die Position auf den Anfang der gewählten Folie (`ScriptFollower.seek(character:holdingFloor:)`). Der Erkenner liefert das laufende Audiosegment in jedem Teilresultat komplett; die vor dem Sprung schon gehörten Wörter gelten deshalb weiter als verbraucht, statt nach dem Sprung als neue Evidenz zu zählen. Zusätzlich darf die globale Suche bis zum nächsten Sprung nicht vor den Anfang der gewählten Folie zurückkehren. Spricht der Sprecher den angefangenen Satz der vorigen Folie zu Ende, gilt das als Einschub; die Markierung wartet auf den Text der neuen Folie. Vorlauf im Sprechtempo und vorgezogene Markierung beginnen neu. Text vor dem Sprung bleibt abgedunkelt (`PrompterSession.spokenThrough`), bis wieder ein Wort erkannt ist. Ein Sprung per Scrollrad setzt keine Untergrenze.

(Eingeführt am 11. November 2026, Version 1.1.1.)

### Schreibweisen angleichen

Bevor die Ausrichtung beginnt, bildet `LexicalBridge` gehörte Wörter auf die Schreibweise des Skripts ab. Apples Erkenner formatiert anders, als ein Skript oft geschrieben ist. Gemessen am 27. Oktober 2026 mit `SpeechTranscriber` und synthetischen Stimmen: kleine Zahlen als Wort („drei“, „zwölf“, „three“), größere als Ziffern („25“, „2026“, „112“), „Dr.“ für „Doktor“, englisch „25%“ und „email“, deutsch ausgeschrieben „zum Beispiel“, „das heißt“, „und so weiter“. Ohne Angleichung zählte jedes solche Wort als fremdes Wort. Weil beim Streaming meist genau das neueste Wort am Ende eines Teilresultats steht, hing die Markierung dann ein bis drei Wörter hinterher.

1. **Zahlen:** Ziffern, deutsche Zahlwörter in einem Wort („zweitausendsechsundzwanzig“) und englische Zahlfolgen („twenty five“, „one hundred and twelve“) werden auf ihren Wert abgebildet. Ordinalzahlen, Dezimalzahlen und „eine Million“ sind nicht enthalten.
2. **Prozentzeichen:** „%“ wird zu „Prozent“/„percent“, wenn das Skript das Wort enthält. Steht im Skript „25 %“, wird ein gehörtes „Prozent“ übergangen.
3. **Bindestriche und Komposita:** „Email“ ↔ „E-Mail“, „Solarmodule“ ↔ „Solar-Module“. Skriptwörter mit Leerzeichen dazwischen werden nie zusammengezogen.
4. **Abkürzungen und Kurzformen:** eine feste Tabelle, z. B. „z. B.“, „d. h.“, „usw.“, „bzw.“, „Dr.“, „Prof.“, „e.g.“, „etc.“ sowie englische Kurzformen („don't“ ↔ „do not“).
5. **Knapp verfehlte Wörter:** Ein gehörtes Wort ab sechs Buchstaben, das nicht im Skript vorkommt, darf als eines der nächsten acht Skriptwörter gelten. Bedingungen: gleicher Anfangsbuchstabe, höchstens ein abweichender Buchstabe (zwei ab zehn Buchstaben) oder ein gemeinsamer Wortstamm mit anderer Endung („Speichern“ → „Speicher“, „battery“ → „batteries“). Es muss genau ein solches Skriptwort in Frage kommen. Das gilt nur, solange kein freier Einschub erkannt ist, und nie für entfernte Sprünge. Die Zuordnung bleibt für das Audiosegment fest, damit spätere Teilresultate nicht als Revision erscheinen.

Grundregeln: Es werden nur Entsprechungen verwendet, die in diesem Skript tatsächlich vorkommen. Ein gehörtes Wort oder eine gehörte Folge, die wörtlich im Skript steht, wird nie umgeschrieben. Danach gelten dieselben Ausrichtungs- und Sprungregeln wie oben; keine Schwelle wurde gesenkt. Ein gehörtes „fünfundzwanzig“ ist danach so viel Evidenz wie ein gelesenes „25“, nicht mehr.

### Halbe Wörter am Ende eines Teilresultats

Mit `.fastResults` endet ein Teilresultat oft mit dem Wort, das gerade noch gesprochen wird: „wie moderne Spei“, „und war“. Bisher scheiterte dann das ganze Ereignis, weil die Ausrichtung auf dem letzten gehörten Wort enden muss; auch das vollständige „moderne“ davor wurde erst mit dem nächsten Ergebnis markiert. Nach einem Treffer galt das Bruchstück außerdem als verbraucht, sodass die Korrektur „nach“ → „nachhaltige“ als Revision verworfen wurde.

Jetzt wird ein letztes Wort zurückgestellt, wenn es nicht im Skript vorkommt oder nur der Anfang eines der nächsten sechs Skriptwörter ist (und nicht selbst eines davon). Voraussetzung: Im selben Ereignis gibt es noch mindestens ein anderes neues Wort. Das Bruchstück zählt weder als Evidenz noch als verbraucht; das nächste Teilresultat wertet das fertige Wort normal aus. Die Sprungregeln bleiben unverändert.

### Zusätzliche lokale Rückkehrprüfung

Wenn sowohl der bisherige lokale Pfad als auch die globale Zuordnung scheitern, prüft ein zusätzlicher begrenzter Pfad die nächsten 16 Skriptwörter. Zwei aussagekräftige, im lokalen Fenster eindeutige Wörter müssen in derselben Reihenfolge auftreten. Zwischen zwei Treffern sind höchstens drei Wörter je Seite erlaubt; die Gesamtzahl der Lücken ist zusätzlich begrenzt. Liegt der erste Treffer mehr als sechs Wörter voraus oder würde der Anschluss mehr als zehn Wörter vorziehen, sind mindestens drei Treffer nötig. Die ersten zehn noch ungelesenen Wörter bilden die späteste mögliche Anfangsposition.

Das überbrückt beispielsweise einen umformulierten Satzanfang und einen Einschub zwischen „Kosten“ und „prüfen“. Es ist ein exakter Wortvergleich mit tolerierten Lücken, keine semantische Interpretation. Ein einzelnes Schlüsselwort, vertauschte Treffer, mehrdeutige lokale Wiederholungen oder weit verstreute Wörter in einer Anekdote genügen nicht.

Bis zu drei zusätzliche gesprochene Wörter nach dem letzten Treffer dürfen im selben Erkennungsereignis mitkommen. Markiert wird nur das letzte bestätigte Skriptwort. Mindestens dieser letzte Treffer muss zum neu eingegangenen Teil gehören: Ein späteres zusätzliches Wort kann alte Treffer nicht erneut nutzen. Pausierte oder bereits verarbeitete Wörter bleiben ausgeschlossen. Pro Endpunkt werden höchstens vier Pfade mit maximal vier Ankern gehalten, bei höchstens zwölf gehörten Wörtern; der zusätzliche Aufwand bleibt begrenzt.

Die Alternative zu einem großen Modell ist hier eine begrenzte gewichtete Sequenzsuche mit dauerhaftem lokalen Anker. Sie ist kein trainiertes HMM und liefert keine kalibrierten Wahrscheinlichkeiten. Die drei möglichen Verläufe – Fortsetzen, Einschub und Wechsel der Stelle – werden durch lokale Regeln, Lückenkosten und strengere globale Evidenzanforderungen unterschieden.

Der Scrollausgleich nutzt den Bildschirmtakt und nähert sich dem Ziel mit einer entfernungsabhängigen Zeitkonstante von 80–160 ms und einer Geschwindigkeitsgrenze. Bei größerem Rückstand holt er schneller auf; nahe der Lesezeile wird er sanfter. Er hängt von verstrichener Zeit statt Bildanzahl ab, überschwingt nicht und extrapoliert keine zukünftigen Wörter. Bei reduzierter Bewegung wird das bekannte Ziel direkt gesetzt.

## Grenzen

Das ist eine konservative, nachvollziehbare Heuristik mit Szenariotests, kein trainiertes Modell für Sprecherabsichten. Sie kann keine freie Paraphrase zuverlässig einem Skript zuordnen und keine andere Person mit denselben Skriptwörtern unterscheiden. Völlig identische wiederkehrende Absätze benötigen zusätzlichen Kontext oder manuelle Navigation. Die 240-Kandidaten-Grenze kann bei extrem repetitiven Skripten sehr entfernte Stellen ausschließen. Erkennungslatenz und Fehler von Apple Speech beeinflussen weiterhin die Markierung. Die Schwellen sind begründete Ausgangswerte; ausgiebige eigene Takes sind wichtig für weitere Feinabstimmung.

## Scrollen im Sprechtempo (ADR-19)

Option unter Einstellungen → Lesen → Prompter, nur im Modus Stimme, standardmäßig aus. Sie ändert weder die Ausrichtung noch die Markierung.

- **Tempo** (`ReadingLead`): aus den bestätigten Wörtern der letzten drei Sekunden; Lücken über 1,5 s zählen als Pause und beginnen neu.
- **Vorlauf:** Zwischen bestätigten Wörtern rückt eine geschätzte Leseposition mit diesem Tempo vor, solange die Stimmaktivität Sprechen meldet, höchstens 24 Zeichen über das zuletzt bestätigte Wort hinaus und höchstens 0,9 s lang. Sie läuft nie von selbst zurück; nur ein Wiedereinstieg setzt sie neu. Abseits des Skripts bleibt sie stehen.
- **Geometrie:** Der Reader bildet die Position stetig ab. Die gesprochene Zeile steigt während des Lesens von der zweiten Zeile an den oberen Rand (`ReaderViewport.continuousVoiceOffset`); die nächste gesprochene Zeile bleibt wie bisher oberhalb des unteren Verlaufs sichtbar.
- **Stimmaktivität** (`VoiceActivity`): Pegel aus dem Eingangsmesser gegen ein sich langsam anpassendes Grundrauschen (mindestens 0,12 oder das Dreifache des Rauschens), mit 0,25 s Haltezeit über kurze Lücken zwischen Silben.

Ein vorläufig markiertes nächstes Wort wurde ebenfalls ausprobiert und nach dem Test des Maintainers entfernt (ADR-19).

## Markierung im Sprechtempo vorziehen (ADR-31)

Option unter Einstellungen → Lesen → Prompter, nur im Modus Stimme, standardmäßig an. Sie ändert weder die Ausrichtung noch die Sprungregeln.

- **Sprechposition** (`ReadingLead.advanceSpoken`): bestätigte Position plus Tempo × (Zeit seit der Bestätigung + 0,45 s Erkennungsverzögerung). Sie steigt nur, solange die Stimmaktivität Sprechen meldet, höchstens 0,9 s nach dem letzten bestätigten Wort, und nie über den Anfang des zweiten Worts nach dem zuletzt erkannten hinaus.
- **Markierung** (`PrompterSession.predictHighlight`): springt auf das Wort, in das die Sprechposition hineinreicht. Liegt sie genau am Anfang des nächsten Worts (direkt nach einer Bestätigung in Stille), bleibt sie auf dem erkannten Wort.
- **Nie zurück:** Meldet die Erkennung danach ein Wort, das die Markierung schon überholt hat, bleibt sie stehen. Nur ein Wiedereinstieg, Hover, Scrollen, Seek oder Zurücksetzen setzt sie neu. Abseits des Skripts bewegt sie sich nicht.

## Sprachen (ADR-30)

Angeboten werden alle Sprachen von `DictationTranscriber.supportedLocales` mit Leerzeichen zwischen Wörtern (`SpeechLanguage.available`). `SpeechLanguage` speichert die BCP-47-Kennung als Zeichenkette. Die Wortausrichtung ist sprachunabhängig; `LexicalBridge` gleicht Zahlwörter nur für Deutsch und Englisch an, die semantische Rückkehr arbeitet nur auf Deutsch und Englisch. Das Vokabular für das Diktat filtert mit dem Wortmodell der jeweiligen Sprache, ohne Wortmodell nimmt es die längsten Skriptwörter. Der Tokenizer zählt kombinierende Zeichen (`\p{M}`) zum Wort. Der Sprachvorschlag in der Seitenleiste nutzt `NLLanguageRecognizer` (mindestens 40 Buchstaben, Konfidenz ≥ 0,8, Regieanweisungen ausgenommen) und stellt nur per Klick um.

## Erkenner: Diktat mit Skriptvokabular (ADR-20)

Erkannt wird immer mit `DictationTranscriber` (ADR-22); ohne Diktiermodell für die Sprache nimmt die App automatisch `SpeechTranscriber`. Das Diktiermodell liefert neue Wörter etwa alle 0,25 s statt alle 0,95 s. Es bekommt als `contextualStrings` die Skriptwörter, die nicht im Wortschatz von Apples Wortmodell (`NLEmbedding`) stehen oder Ziffern bzw. Großbuchstaben im Inneren haben, längste zuerst, höchstens 50 (`SpeechService.dictationVocabulary`). Jeder Eintrag kostet beim Start ~5,5 ms. Die Wortausrichtung ist für beide Erkenner dieselbe.

## Latenzdiagnose

`SpeechLatencyMetrics` hält höchstens 256 Messpunkte im Arbeitsspeicher, ohne Audio oder Transkript. Die Zusammenfassung des letzten Takes steht unter Einstellungen → Diagnose → Sprachdiagnose: Ereignisse und Anteil mit Fortschritt, „Wortende → erkannt“ (erstes Erscheinen eines Worts in einem vorläufigen Ergebnis gegen sein Ende laut finalem Ergebnis; bis 28.10.2026 fälschlich gegen das Ende des ganzen Teilresultats gemessen), „Neue Wörter alle“ (Abstand der Ergebnisschübe), Wörter erst im finalen Ergebnis (gezählt, nicht in die Latenz gemischt), Rückkehr per Satzmodell, der verwendete Erkenner, Median und p95 für Erkennung, Zuordnung und Markierung, Ergebnisse ab einer Sekunde, revidierte Teilresultate, Ereignisse ohne Fortschritt nach Grund (neuestes Wort nicht im Skript, Stelle noch nicht eindeutig, Einschub, Wiederholung, Revision, nichts Neues, pausiert), tatsächliche Audioblockgröße und Startzeit samt Mikrofonanteil. Sie wird beim Zurücksetzen des Takes gelöscht. Erfasst werden Zuordnungsdauer, revidierte Teilresultate, ein optionaler geschätzter Abstand zum Ende des erkannten Audioabschnitts und die Zeit bis zum Anwenden der Textmarkierung. Der letzte Wert misst keinen tatsächlichen Bildschirm-Scanout. Die Audiozeit wird anhand der Audio-Callbacks auf die monotone Laufzeit abgebildet; Mikrofon-/Hardwarelatenz und ungenaue Erkenner-Zeitstempel sind damit nicht unabhängig messbar. Kein Upload, kein automatisches Protokoll auf Platte. Ergebnisse und Grenzen: [SPEECH_LATENCY_RESULTS.md](SPEECH_LATENCY_RESULTS.md).

## Optionale Modellhilfe

Im Modus Stimme läuft immer eine lokale semantische Apple-Modellhilfe mit (ADR-22). Sie ergänzt ausschließlich fehlgeschlagene Wortzuordnungen. Ablauf, Positionsschutz und Grenzen sind in [SEMANTIC_RECOVERY.md](SEMANTIC_RECOVERY.md) beschrieben.
