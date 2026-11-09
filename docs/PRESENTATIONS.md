# PDF-Präsentationen

Stand: 26. Oktober 2026. Betrifft `Core/Presentation.swift`, `Services/PresentationFiles.swift`, `Services/PresentationController.swift`, `Views/SlideEditorView.swift`, `Views/PresentationViews.swift` und die Foliensynchronisation in `Core/Session.swift`.

## Ziel

Ein Skript kann mit einer PDF verknüpft werden, z. B. aus Keynote, PowerPoint oder Google Slides exportiert. Für jede Folie oder Foliengruppe gibt es einen eigenen Text. Beim Präsentieren wechseln die Folien, sobald ihr Text gelesen ist. Umgekehrt springt der Prompter zum passenden Text, wenn eine Folie manuell gewechselt wird.

## Datenmodell

`Script.presentation: PresentationDeck?` ist optional. Ältere `scripts.json` werden daher unverändert gelesen.

- `SlidePage`: eine PDF-Seite mit stabiler ID und Fingerabdruck. Der Fingerabdruck besteht aus normalisiertem Seitentext (höchstens 600 Zeichen) und einem 64-Bit-Differenz-Hash einer kleinen Graustufenvorschau. Dazu kommen optionale Markierungen `added` und `changed` nach einem Update.
- `SlideSection`: Text plus eine oder mehrere Seiten-IDs (Gruppe). Die Reihenfolge der Abschnitte ist die Lesereihenfolge.
- Die PDF selbst liegt als Kopie unter `Application Support/macprompter/Presentations/<deck-id>.pdf`. Zusätzlich speichert die App ein Security-Scoped Bookmark zur Originaldatei (Entitlement `com.apple.security.files.bookmarks.app-scope`, ADR-8).

## Folien und Schritte

Eine *Folie* ist ein Abschnitt, also das, was das Publikum als eine Folie wahrnimmt. Gehören mehrere PDF-Seiten zu einem Abschnitt, sind das *Schritte*, z. B. schrittweise aufgedeckte Punkte aus einem Keynote- oder PowerPoint-Export. Nummeriert wird nach Folien („Folie 3 · 3 Schritte“), die PDF-Seiten stehen im Editor als Zusatzinfo. Navigation (Pfeiltasten, Fernbedienung, iPhone) geht immer einen Schritt bzw. eine PDF-Seite weiter. Anzeige: „Folie 3 von 10 · Schritt 2/3“. Seit 26.10.2026; vorher hieß eine Gruppe „Folien 3–5“. Gespeicherte Präsentationen leitet `ScriptLibrary` beim Laden neu ab.

## Abgeleiteter Skripttext

`PresentationComposer.compose` erzeugt aus den Abschnitten den normalen `Script.body`:

```
[Start · Folie 1]
Willkommen …
[Nächste Folie]

[Start · Folie 2 · 2 Schritte]
Erst der Markt. [Weiter] Dann unser Anteil.
[Ende der Präsentation]
```

Regieanweisungen in Klammern zählen nicht als gesprochene Wörter. Sprachführung, Reader, Wortzählung und Suche arbeiten daher unverändert mit dem abgeleiteten Text. Der Text wird nach jeder Änderung neu erzeugt. Eine ältere App-Version, die `presentation` nicht kennt, zeigt immer noch einen lesbaren Text.

Gleichzeitig entsteht eine `SlideTimeline`, also Zeichenpositionen mit der zugehörigen Seite:

- Die erste Seite eines Abschnitts beginnt an der Marke `[Nächste Folie]` des vorherigen Abschnitts. Der Sprungpunkt beim manuellen Wechsel ist die Startmarke des Abschnitts.
- In Gruppen wechselt `[Weiter]` (auch `[Klick]`, `[Next]`, `[Click]`) zur nächsten Seite. Ohne solche Marken verteilen sich die Seiten gleichmäßig nach gesprochenen Wörtern.
- Abschnitte ohne Seite (Folie aus der PDF gelöscht) erzeugen keinen Wechsel. Ihr Text bleibt erhalten.

## Synchronisation

- **Stimme:** Nach jedem erkannten Wort gilt die Seite des *nächsten* Skriptworts. Die Folie wechselt also, sobald das letzte Wort ihres Abschnitts erkannt ist. Abschnitte ohne Text werden im Sprachmodus übersprungen, und der Editor weist darauf hin.
- **Automatisch/Manuell:** Der Reader meldet bei jeder Scrollbewegung das Zeichen in der Fokuszeile (`readerReached`). Die Folie wechselt, wenn die Marke `[Nächste Folie]` die Fokuszeile erreicht.
- **Manuelles Bewegen in jedem Modus (seit 27.10.2026):** Scrollrad, Tasten und iPhone melden die Fokuszeile auch im Sprachmodus (`readerReached(…, manual: true)`), auch während Hover. Zusätzlich setzt die Wortausrichtung dort neu auf. Vorher wechselte im Sprachmodus nur das Sprechen die Folie.
- **Manuell (Pfeiltasten, Presenter-Fernbedienung, ⌥⌘←/→ während der Präsentation):** `stepSlide` wechselt die Folie immer. Der Prompter springt nur, wenn die `PlaybackGate` Bewegung erlaubt; Hover und Countdown haben also Vorrang. Im Sprachmodus setzt die Wortausrichtung am Sprungpunkt neu auf, Audio aus der Zeit davor wird verworfen.
- Wechsel sind flankengesteuert: Die Leseposition ändert die Folie nur, wenn sich *ihre* Seite ändert. Ein manueller Wechsel bleibt also bestehen, bis der Text tatsächlich weiterläuft. Nach einem manuellen Sprung übernimmt die Fokuszeile die gewählte Seite einmalig, weil sie knapp vor der Marke landen kann.
- **Abschaltbar (seit 27.10.2026):** Einstellungen → Steuerung → Folien → „Folien wechseln mit dem Lesefortschritt“ (`Preferences.slidesFollowReading`, global, Standard an). Ausgeschaltet ändern Stimme und Fokuszeile die Folie nicht mehr, unabhängig davon, wodurch der Text bewegt wurde (Timer, Stimme, Scrollrad, Tasten, iPhone). Manuelle Folienwechsel funktionieren unverändert und lassen den Prompter mitspringen. Wieder eingeschaltet greift die Synchronisation ab der nächsten Marke, ohne nachträglichen Sprung.

## PDF in Arbeit: Updates

Beim Öffnen des Editors, beim Aktivieren der App und vor dem Präsentieren prüft macprompter Änderungsdatum und Größe der Originaldatei. Während einer laufenden Präsentation wird nichts neu eingelesen. Bei einer Änderung richtet `SlideMatcher.align` die alte und die neue Seitenfolge aneinander aus:

1. **Reihenfolgetreue Ausrichtung** (gewichtete LCS, O(n·m)): Ähnlichkeit = 0,75 · Jaccard der Seitenwörter + 0,25 · Bild-Hash-Ähnlichkeit. Ohne Text zählt nur das Bild. Treffer ab 0,5.
2. **Verschobene Folien:** Noch offene Seiten mit Ähnlichkeit ab 0,8 werden auch außerhalb der Reihenfolge zugeordnet.
3. **Bearbeitete Folien:** Liegen zwischen zwei sicheren Treffern gleich viele offene alte und neue Seiten, werden sie der Position nach gepaart und als „Geändert · prüfen“ markiert.

Danach behalten zugeordnete Seiten ihre ID und damit ihren Text. Eine neue Seite zwischen zwei Seiten derselben Gruppe kommt in diese Gruppe, sonst bekommt sie einen leeren Abschnitt mit der Markierung „Neu“. Text gelöschter Seiten bleibt als „Ohne Folie“ an seiner bisherigen Stelle, bis er ausdrücklich gelöscht wird. Die Abschnitte werden nach der neuen Seitenreihenfolge sortiert.

Das Einlesen (Text, Hash) läuft außerhalb des MainActor. Übernommen wird das Ergebnis synchron in den *aktuellen* Stand des Skripts, damit gleichzeitig getippter Text nicht verloren geht. Ist das Original nicht erreichbar, bleibt die Kopie in Gebrauch. „Neue PDF-Version wählen …“ verknüpft eine andere Datei mit derselben Zuordnungslogik.

## Präsentationsmodus

- **Folien:** randloses Fenster über dem ganzen Bildschirm. Vektorzeichnung der Seite auf Papierweiß, seitenverhältnistreu auf Schwarz. Auf dem Hauptbildschirm werden Dock und Menüleiste ausgeblendet.
- **Bildschirmwahl:** Einstellung „Folien auf“. Automatisch wird ein anderer Bildschirm als der des Prompters gewählt, bei nur einem Bildschirm derselbe. Der Prompter liegt dann über den Folien.
- **Referentenansicht** (optional, Standard an): erscheint nur bei zwei Bildschirmen, auf dem Bildschirm des Prompters. Sie zeigt aktuelle und nächste Folie, „Folie x von y“, die Laufzeit mit Knopf zum Zurücksetzen (setzt auch die Zeit im Prompter zurück), Start/Pause des Takes, Schwarzbild und Beenden. Der Bereich unter dem angedockten Prompter bleibt frei.
- **Tasten:** → ↓ Leertaste Bild↓ Return = weiter; ← ↑ Bild↑ Rückschritt = zurück; Pos1/Ende; B oder . = Schwarzbild; Esc = beenden. Diese Tasten decken die üblichen Presenter-Fernbedienungen ab. ⌥⌘←/→ sind nur während der Präsentation global registriert.
- Wird ein Bildschirm ab- oder angesteckt, baut die App die Fenster auf den vorhandenen Bildschirmen neu auf.

## Grenzen

- Foliensynchronisation gilt nur für die PDF-Ansicht von macprompter. Keynote oder PowerPoint werden nicht ferngesteuert.
- Animationen und Videos aus der Originalpräsentation gibt es nur als exportierte Einzelseiten (Aufbau-Schritte als Gruppe).
- Stark umgebaute Folien ohne Textübereinstimmung zählen als neu und gelöscht. Dabei geht kein Text verloren, er steht dann unter „Ohne Folie“.
- Die Zuordnung ist eine Heuristik mit Szenariotests (`SlideMatcherTests`), keine Garantie. Nach einem Update deshalb die markierten Folien prüfen.
