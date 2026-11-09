# Software und Inhalte Dritter

macprompter selbst steht unter der [MIT-Lizenz](LICENSE). Das Projekt nutzt keine Swift-Pakete oder anderen Fremdbibliotheken. Folgende Bestandteile stammen von Dritten oder sind aus deren Arbeit abgeleitet. Stand der Prüfung: 9. November 2026.

| Bestandteil | Wo | Herkunft | Lizenz |
| --- | --- | --- | --- |
| OpenDyslexic (Schrift, unverändert) | `MacPrompter/Resources/Fonts/` und in der App | Abbie Gonzalez, <https://opendyslexic.org> | SIL Open Font License 1.1, Reserved Font Name „OpenDyslexic“ ([OFL.txt](MacPrompter/Resources/Fonts/OFL.txt)) |
| Agent-Skills `macos-build`, `macos-notch-ui`, `macos-patterns`, `macos-release`, `macos-settings-ui` | `.agents/skills/` (gespiegelt nach `.claude/skills/`), Herkunft in `skills-lock.json` | Fayaz Ahmed, <https://github.com/fayazara/macos-app-skills> | MIT (Text unten) |
| Notch-Form (`NotchShape` in `OverlayView.swift`) | in der App | abgeleitet aus `macos-notch-ui/references/NotchShape.swift` derselben Skills | MIT (Text unten) |

Die Lizenztexte werden auch mit der App ausgeliefert (Hilfe → Lizenzen und Danksagungen).

## Nicht Teil des Repositorys

- **Apple-Frameworks** (Speech, NaturalLanguage, AppKit, SwiftUI, PDFKit, Network u. a.) und die Sprach- und Satzmodelle gehören zu macOS und werden weder mitgeliefert noch weitergegeben.
- **Testaudios** der Sprachtests erzeugt `scripts/make_fixtures.sh` lokal mit den macOS-Systemstimmen. Apples Lizenz erlaubt nicht, deren Ausgabe zu veröffentlichen; deshalb sind sie nicht eingecheckt (ADR-24). Ältere Commits enthalten die früheren Dateien noch.
- **Screenshots und Demo-Video** in `docs/media/` zeigen ausschließlich macprompter mit Demo-Inhalten des Projekts (Beispielpräsentation aus `scripts/MakeSampleDeck.swift`, Systemschrift). Kein Ton, keine Musik.
- **Inspiration:** [Moody](https://moody.mjarosz.com/) und [NotchPrompter](https://notchprompter.com/) für den Funktionsumfang. Eigenständige Implementierung, kein übernommener Code.

## MIT-Lizenz von macos-app-skills

```
MIT License

Copyright (c) 2026 Fayaz Ahmed

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Das Repository von macos-app-skills nennt die MIT-Lizenz in seiner README, enthält aber keine eigene Lizenzdatei. Copyright-Inhaber und Jahr sind aus Autor und Erstellungsdatum des Repositorys übernommen.
