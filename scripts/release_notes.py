#!/usr/bin/env python3
"""Release metadata from the repository, used by the release workflow and scripts/package_release.sh.

  release_notes.py --version                 app version (MARKETING_VERSION in generate_project.py)
  release_notes.py --check v1.2.3            tag, version and CHANGELOG section must agree
  release_notes.py --notes <signing-mode>    release notes as Markdown (CHANGELOG section + install guide)

Release notes come from CHANGELOG.md: each version needs a section "## [x.y.z] – YYYY-MM-DD"
with a short summary paragraph and at least one list entry (docs/RELEASING.md).
"""
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
REPO = 'https://github.com/FNG-2002/macprompter'


def version():
    match = re.search(r"'MARKETING_VERSION':'([^']+)'", (root / 'scripts/generate_project.py').read_text())
    if not match:
        sys.exit('error: MARKETING_VERSION not found in scripts/generate_project.py')
    return match.group(1)


def section(changelog, v):
    """Returns (date, body) of the CHANGELOG section for version v."""
    match = re.search(r'^## \[' + re.escape(v) + r'\] – (\d{4}-\d{2}-\d{2})[^\n]*\n(.*?)(?=^## \[|\Z)', changelog, re.M | re.S)
    if not match:
        sys.exit(f'error: CHANGELOG.md has no section "## [{v}] – YYYY-MM-DD"')
    return match.group(1), match.group(2).strip()


def check(tag):
    v = version()
    if not re.fullmatch(r'\d+\.\d+\.\d+', v):
        sys.exit(f'error: version {v} is not x.y.z')
    if tag != f'v{v}':
        sys.exit(f'error: tag {tag} does not match app version v{v}; bump MARKETING_VERSION first')
    _, body = section((root / 'CHANGELOG.md').read_text(), v)
    summary = body.split('\n\n', 1)[0]
    if summary.startswith(('#', '-')) or len(summary) < 40:
        sys.exit(f'error: CHANGELOG section {v} needs a summary paragraph of at least one sentence before the lists')
    if not re.search(r'^- ', body, re.M):
        sys.exit(f'error: CHANGELOG section {v} has no list entries')
    print(f'OK {tag}')


INSTALL = {
    'notarized': 'Die App ist mit Developer ID signiert und von Apple notarisiert. Sie startet nach dem Kopieren ohne Warnung.',
    'developer-id': 'Die App ist mit Developer ID signiert, aber nicht notarisiert. Beim ersten Start: Rechtsklick auf die App → „Öffnen“, oder Systemeinstellungen → Datenschutz & Sicherheit → „Dennoch öffnen“.',
    'self-signed': ('Die App ist mit dem eigenen Zertifikat des Projekts signiert, aber nicht von Apple notarisiert '
                    '(dafür bräuchte es eine kostenpflichtige Apple-Mitgliedschaft). macOS blockiert deshalb den ersten Start:\n\n'
                    '1. App öffnen, die Meldung „Apple konnte nicht überprüfen …“ mit „Fertig“ schließen.\n'
                    '2. Systemeinstellungen → Datenschutz & Sicherheit → ganz unten bei macprompter „Dennoch öffnen“ wählen und bestätigen.\n\n'
                    'Alternativ im Terminal: `xattr -dr com.apple.quarantine /Applications/macprompter.app`\n\n'
                    'Weil das Zertifikat über alle Versionen gleich bleibt, behält macOS Freigaben wie Mikrofon und Eingabeüberwachung bei Updates.'),
    'adhoc': ('Die App ist nur ad hoc signiert und nicht notarisiert. macOS blockiert den ersten Start: '
              'Systemeinstellungen → Datenschutz & Sicherheit → „Dennoch öffnen“. '
              'Freigaben wie Mikrofon und Eingabeüberwachung müssen nach jedem Update neu erteilt werden.'),
}


def notes(mode):
    v = version()
    date, body = section((root / 'CHANGELOG.md').read_text(), v)
    body = re.sub(r'^### ', '## ', body, flags=re.M)
    # Relative links do not resolve on the release page.
    body = re.sub(r'\]\((?!https?:|#)([^)]+)\)', lambda m: f']({REPO}/blob/v{v}/{m.group(1)})', body)
    dmg = f'macprompter-{v}.dmg'
    return f"""{body}

## Installation

1. `{dmg}` herunterladen und öffnen.
2. macprompter in den Ordner „Programme“ ziehen.

**Erster Start:** {INSTALL[mode]}

Updates: Die App prüft nicht selbst online nach neuen Versionen. Neue Versionen erscheinen hier unter Releases; einfach die neue DMG installieren, Skripte und Einstellungen bleiben erhalten.

## Systemvoraussetzungen

- macOS 26 oder neuer. Getestet auf Apple Silicon; der Build ist universell, Intel-Macs sind ungetestet.
- Sprachsteuerung: Deutsch oder Englisch über Apples lokale Spracherkennung. macOS lädt das Sprachmodell beim ersten Take gegebenenfalls herunter.
- Die iPhone-Fernbedienung **macprompter Remote** gibt es nur als Quellcode zum Selbstbauen mit Xcode (siehe README).

## Prüfsumme

SHA-256 steht in `{dmg}.sha256`. Prüfen mit `shasum -a 256 -c {dmg}.sha256`.

Gebaut von GitHub Actions aus dem Tag `v{v}` ({date}). Vollständiger Verlauf: [CHANGELOG.md]({REPO}/blob/v{v}/CHANGELOG.md)
"""


if __name__ == '__main__':
    args = sys.argv[1:]
    if args == ['--version']:
        print(version())
    elif len(args) == 2 and args[0] == '--check':
        check(args[1])
    elif len(args) == 2 and args[0] == '--notes' and args[1] in INSTALL:
        print(notes(args[1]))
    else:
        sys.exit(__doc__)
