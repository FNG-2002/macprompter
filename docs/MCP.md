# Zugang für KI-Agenten (MCP)

Stand: 26. Oktober 2026, ergänzt am 1. November 2026 (stdio-Helfer). Betrifft `Services/MCPServer.swift`, `Services/AgentTools.swift`, `Services/MCPBridge.swift`, `MacPrompterMCP/`, `Core/JSONValue.swift`, `Views/MCPSettingsSections.swift`.

## Ziel

Claude und andere Agenten sollen Skripte und Präsentationen samt Sprechtext pro Folie direkt in macprompter anlegen und bearbeiten können (Issue #10), z. B. nachdem sie eine Präsentation erstellt haben.

## Entscheidung: MCP in der App, Streamable HTTP auf 127.0.0.1

- **Warum in der App und nicht als CLI:** Die Bibliothek gehört der laufenden App, sie hält sie im Speicher und speichert entprellt. Ein separates Programm, das `scripts.json` parallel schreibt, würde Änderungen gegenseitig überschreiben. Außerdem kann es wegen der Sandbox nicht sauber auf den Container zugreifen. Der Server in der App nutzt dieselben Wege wie die Oberfläche, Änderungen erscheinen sofort im Editor.
- **Warum HTTP statt stdio:** Ein stdio-Server müsste ein eigenes Hilfsprogramm sein, mit eigenem Target, eigener Signatur und Netzwerkzugriff zur App. Streamable HTTP ist der MCP-Standardtransport für Server, die als Dienst laufen. Claude Code bindet ihn direkt ein. Clients, die nur lokale Programme starten, nutzen einen HTTP-Adapter wie `mcp-remote`.
- **Keine neuen Berechtigungen:** Das vorhandene Entitlement `network.server` (ADR-9) genügt, Loopback braucht keine Freigabe für das lokale Netzwerk. Keine externen Pakete: HTTP/1.1-Parser und JSON-RPC sind bewusst minimal selbst implementiert.

## Einrichten

Einstellungen → KI-Agenten → „Zugriff für KI-Agenten (MCP)“ einschalten. Standardport `47823`, änderbar.

```sh
claude mcp add --transport http macprompter http://127.0.0.1:47823/mcp \
  --header "Authorization: Bearer <Token aus den Einstellungen>"
```

Für andere Clients steht in den Einstellungen eine fertige JSON-Konfiguration (`type: http`, `url`, `headers`). macprompter muss laufen, solange ein Agent arbeitet.

### Claude Desktop und Cowork (stdio)

Claude Desktop und Cowork binden lokale Server nur als Programm ein, das über stdio spricht; eigene Connectors mit HTTP-Adresse laufen über Anthropics Server und erreichen `127.0.0.1` nicht. Dafür liegt in der App das Hilfsprogramm `macprompter.app/Contents/Helpers/macprompter-mcp`. Die fertige Konfiguration steht unter Einstellungen → KI-Agenten → Einrichten („Claude Desktop und Cowork“) und gehört in Claude Desktop unter Einstellungen → Entwickler → Konfiguration bearbeiten in `mcpServers`:

```json
{"mcpServers": {"macprompter": {"command": "/Applications/macprompter.app/Contents/Helpers/macprompter-mcp",
  "env": {"MACPROMPTER_MCP_TOKEN": "<Token aus den Einstellungen>", "MACPROMPTER_MCP_PORT": "47823"}}}}
```

Danach Claude Desktop neu starten. Der Helfer reicht jede JSON-RPC-Zeile von stdin per `POST /mcp` an die App weiter und schreibt die Antwort als eine Zeile nach stdout; Benachrichtigungen bekommen keine Antwort. Läuft macprompter nicht, startet der Helfer die App, in der er liegt, im Hintergrund (ohne sie zu aktivieren) und wartet bis zu 15 s auf den Server. Läuft die App, aber der MCP-Zugang ist aus, antwortet er sofort mit einer deutschen Fehlermeldung, ebenso bei falschem Token. Nach einem neuen Token, einem anderen Port oder dem Verschieben der App die Konfiguration neu kopieren.

## Nachtrag 1. November 2026: stdio-Helfer

Die Entscheidung für HTTP in der App bleibt: Der Helfer ist nur ein Adapter und hält keinen eigenen Zustand, die App bleibt alleinige Besitzerin der Bibliothek. Er hat ein eigenes Target (`macprompter-mcp`, Kommandozeilenprogramm), wird beim Bauen nach `Contents/Helpers` kopiert und mitsigniert. Er läuft in einer eigenen Sandbox mit nur einem Entitlement, `network.client`, um die App auf `127.0.0.1` zu erreichen; Dateizugriff hat er keinen. Die App selbst bekommt keine neue Berechtigung (ADR-23). Token und Port bekommt er über Umgebungsvariablen aus der Client-Konfiguration, weil er den Container der App nicht lesen darf. Die Weiterleitung steckt in `MCPBridge` (auch in die App kompiliert, für die Konfiguration in den Einstellungen und die Tests), `MacPrompterMCP/main.swift` liest nur stdin, schreibt stdout und startet die App.

## Werkzeuge

| Werkzeug | Zweck |
| --- | --- |
| `list_scripts` | Alle Skripte mit id, Titel, Sprache, Wortzahl, Folienanzahl |
| `get_script` | Text eines Skripts bzw. pro Folie: Nummer, Sprechtext, PDF-Seiten, Schritte, Markierungen |
| `create_script` | Neues Skript (Titel, Text, Sprache `de`/`en`) |
| `update_script` | Titel, Sprache, Text (Text nur bei normalen Skripten) |
| `create_presentation` | Präsentation aus PDF (`pdf_path` im freigegebenen Ordner oder `pdf_base64`), optional Texte und Schritte pro Folie |
| `set_slide_text` | Sprechtext einer Folie (Nummer ab 1 oder `section_id`) |
| `set_slides` | Alle Folientexte in Reihenfolge; mit `steps` auch Gruppierung der PDF-Seiten |
| `replace_presentation_pdf` | Neue PDF-Version; Texte bleiben ihren Folien zugeordnet (siehe [PRESENTATIONS.md](PRESENTATIONS.md)) |
| `export_script` | Als `.macprompter`-Datei in den freigegebenen Ordner (`path`) oder als `file_base64` |
| `import_script` | `.macprompter`-Datei aus dem Ordner oder als Base64 als neues Skript laden |
| `select_script` | Skript im Editor öffnen |

Fehler (unbekannte id, Schritte passen nicht zur Seitenzahl, Datei außerhalb des Ordners) kommen als Werkzeugergebnis mit `isError: true` und deutscher Erklärung zurück, damit der Agent sich korrigieren kann. Neue Skripte werden nicht automatisch ausgewählt, um laufende Eingaben nicht zu stören.

**Bewusst nicht enthalten:** Löschen von Skripten (Nutzerdaten sind heilig) und Wiedergabesteuerung (dafür gibt es Tastenkürzel und die iPhone-App).

## Dateien und Sandbox

Die sandboxed App darf nur Dateien lesen und schreiben, die der Nutzer freigibt. Unter „Dateien von und für Agenten“ wählt man deshalb einmal einen Ordner (für PDFs und `.macprompter`-Dateien), die App merkt ihn sich per Security-Scoped Bookmark in `mcp.json`. `pdf_path` muss in diesem Ordner liegen, absolut oder relativ. Pfade, die aus dem Ordner herausführen (`../`, Symlinks), werden abgelehnt. Präsentationen aus dem Ordner werden wie importierte PDFs beobachtet, ein neuer Export wird also auch ohne Agent übernommen. Kleine PDFs können Agenten alternativ als `pdf_base64` schicken.

## Sicherheit

- Nur `127.0.0.1`, nicht im lokalen Netz erreichbar (geprüft: Verbindung über die LAN-Adresse wird abgewiesen).
- Bearer-Token, 256 Bit zufällig, in `mcp.json` (Dateirechte 0600) neben `scripts.json`, in den Einstellungen neu erzeugbar. Vergleich in konstanter Zeit. Eine unlesbare `mcp.json` wird nie überschrieben.
- Schutz gegen DNS-Rebinding: `Origin` und `Host` müssen lokal sein, sonst `403`.
- Standardmäßig aus. Protokolliert werden nur Werkzeugname und Uhrzeit, im Arbeitsspeicher, keine Inhalte.
- **Grenze:** Jedes lokale Programm mit dem Token kann Skripte lesen und ändern. Wer den Token einem Agenten gibt, gibt ihm Zugriff auf die Skripttexte.
- Der stdio-Helfer ändert daran nichts: Er braucht denselben Token und spricht nur mit `127.0.0.1`. Der Token steht dabei im Klartext in der Konfiguration von Claude Desktop, genau wie in der HTTP-Konfiguration anderer Clients.

## Protokoll

JSON-RPC 2.0 über `POST /mcp`, Antworten als `application/json` (kein SSE nötig; `GET` → `405`). Unterstützte Versionen: `2025-11-25`, `2025-06-18`, `2025-03-26`; bei unbekannter Version antwortet der Server mit der neuesten. Benachrichtigungen → `202`. Keine Sitzungs-IDs (zustandslos). Anfragekörper bis 64 MB (für `pdf_base64`).

## Prüfung

- XCTest: stdio-Helfer (Konfiguration aus Umgebungsvariablen, Fehler nur für Anfragen, ein Start der App für gleichzeitige Anfragen, kein Warten bei ausgeschaltetem Zugang, Ende-zu-Ende über Loopback, Claude-Desktop-Konfiguration), Parser, Zugriffsschutz, Versionsaushandlung, alle Werkzeuge mit echter Bibliothek und echten PDFs, Ordnergrenzen, Token-Ablage, Loopback-Aufruf über `URLSession`.
- Ende-zu-Ende am 1.11.2026 (stdio): Helfer aus der installierten App in `/Applications` (Apple-Development-Signatur). Bei beendeter App startete er macprompter im Hintergrund und beantwortete `ping` nach etwa 2 s. Claude Code (`claude -p --mcp-config … --strict-mcp-config` mit `command`/`env`) rief `list_scripts` über stdio auf und antwortete korrekt, ebenfalls bei zuvor beendeter App. Claude Desktop und Cowork selbst wurden nicht automatisch geprüft; der Maintainer bestätigte am selben Tag, dass es in Cowork funktioniert.
- Ende-zu-Ende am 26.10.2026: Debug-App mit `-MCPDebugPort` (nur Debug-Builds) gestartet. `curl` prüfte initialize, Benachrichtigung, tools/list, list_scripts, 401 ohne Token und 405 für GET. Claude Code (`claude -p --mcp-config … --strict-mcp-config`) rief `list_scripts` als echter MCP-Client auf und antwortete korrekt. Schreibende Werkzeuge wurden dabei nicht auf die echte Bibliothek angewendet, sie sind über die Tests abgedeckt.
