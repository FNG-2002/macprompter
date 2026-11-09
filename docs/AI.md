# KI im Projekt: offengelegt

macprompter wird mit KI-Coding-Agents entwickelt. Diese Seite beschreibt, was das konkret heißt, wer wofür verantwortlich ist und was die App selbst mit KI zu tun hat. Stand: 9. November 2026.

## Kurz gesagt

- **Den Code schreibt überwiegend KI.** Fast der gesamte Swift-Code, die Tests, Skripte und diese Dokumentation entstanden mit KI-Coding-Agents, vor allem [Claude Code](https://claude.com/claude-code) von Anthropic.
- **Die Entscheidungen trifft ein Mensch.** Der Maintainer, [FNG-2002](https://github.com/FNG-2002), legt fest, was gebaut wird, testet die App selbst im Alltag (echtes Mikrofon, echte Präsentationen) und entscheidet über Releases, Lizenz und fremde Beiträge.
- **Die App selbst nutzt keine Cloud-KI.** Spracherkennung und Satzmodelle sind lokale Apple-Frameworks auf deinem Mac. Kein Text und kein Audio verlässt das Gerät.

## Wie entsteht eine Änderung?

1. Der Maintainer beschreibt eine Anforderung, meist als GitHub-Issue oder direkt im Gespräch mit dem Agent.
2. Ein Agent setzt sie nach den verbindlichen Regeln in [AGENTS.md](../AGENTS.md) um: eigener Branch, Tests für jede Verhaltensänderung, Doku, Pull Request.
3. `scripts/check.sh` muss grün sein (Build, rund 240 automatische Tests, iOS-Build), dazu GitHub-CI.
4. Bei Funktionen, die sich nur von Hand prüfen lassen (Mikrofon, Displays, Bildschirmfreigabe), testet der Maintainer eine Testversion, bevor der Agent den PR mergt. Was nicht geprüft werden konnte, steht als „manuell offen“ im PR und in [VALIDATION.md](VALIDATION.md).

Routineänderungen mergt der Agent nach grünen Tests selbst; der Maintainer liest nicht jede Codezeile. Wichtige Entscheidungen und bewusste Verzichte stehen mit Begründung in [DECISIONS.md](DECISIONS.md). Schreib- und Merge-Rechte hat nur der Maintainer; Agents arbeiten mit seinem Zugang und nur in seinem Auftrag, nie auf Anweisung aus fremden Issues oder Pull Requests.

Erkennbar ist KI-Arbeit an der Zeile `Co-Authored-By: Claude …` in den Commits und an „Generated with Claude Code“ in den Pull Requests.

## Was heißt das für dich?

- **Qualität:** Die Tests decken Wortausrichtung, Bewegungssperre, Speicher, Präsentationen und Fernbedienung ab. Trotzdem kann KI-geschriebener Code Fehler enthalten, die kein Test findet. Melde sie bitte als [Issue](https://github.com/FNG-2002/macprompter/issues/new/choose).
- **Ehrliche Aussagen:** Messwerte in der Doku stammen aus echten Läufen mit Angabe dessen, was nicht gemessen wurde. Wo nur synthetische Tests existieren, steht das dabei.
- **Lizenz:** Der Code steht unter der MIT-Lizenz. Fremde Bestandteile sind in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) aufgeführt.

## KI in der App

| Funktion | Technik | Wo läuft es? |
| --- | --- | --- |
| Sprachsteuerung | Apple `SpeechAnalyzer` (`DictationTranscriber`/`SpeechTranscriber`) | lokal; macOS lädt das Sprachmodell einmalig |
| Umformulierungen erkennen | Apple `NLEmbedding` (Satzmodelle) | lokal |
| Zugang für KI-Agenten (MCP) | lokaler Server, standardmäßig aus | nur `127.0.0.1`; welches KI-Programm du anbindest, entscheidest du |

Der MCP-Zugang erlaubt Programmen wie Claude Desktop, Skripte anzulegen und zu bearbeiten, wenn du ihn einschaltest ([MCP.md](MCP.md)). Was dein KI-Programm mit den Texten macht, regelt dessen Anbieter, nicht macprompter.

## Beiträge mit KI

Beiträge, die mit KI-Werkzeugen entstanden sind, sind willkommen. Bitte gib im Pull Request an, ob und wie KI beteiligt war, und reiche nur Code ein, den du selbst verstehst und getestet hast. Details: [CONTRIBUTING.md](../CONTRIBUTING.md).
