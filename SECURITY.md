# Sicherheit

## Lücke melden

Bitte melde Sicherheitslücken **nicht** als öffentliches Issue, sondern vertraulich über GitHub: [Sicherheitslücke melden](https://github.com/FNG-2002/macprompter/security/advisories/new) (Reiter „Security“ → „Report a vulnerability“).

Beschreibe, was betroffen ist, wie es sich nachstellen lässt und welche Version du nutzt. Du bekommst in der Regel innerhalb einer Woche eine Rückmeldung. macprompter ist ein Ein-Personen-Projekt ohne Bug-Bounty.

## Unterstützte Versionen

Sicherheitskorrekturen erscheinen nur für die jeweils neueste Version.

## Besonders interessante Bereiche

- **MCP-Zugang** (`MCPServer`, `macprompter-mcp`): lokaler HTTP-Server auf `127.0.0.1` mit Bearer-Token, standardmäßig aus.
- **iPhone-Fernbedienung** (`RemoteServer`, `Shared/`): lokales Netz, TLS mit vorab geteiltem Schlüssel, Kopplung per sechsstelligem Code, standardmäßig aus ([docs/REMOTE.md](docs/REMOTE.md)).
- **Sandbox und Entitlements** der App und des Helfers.
- **Datei-Import** (`.macprompter`, PDF, TXT/Markdown/RTF).

Bekannte, bewusste Grenze: Der Aufnahmeschutz des Prompters (`sharingType = .none`) ist keine Garantie gegen Bildschirmaufnahmen (siehe README).
