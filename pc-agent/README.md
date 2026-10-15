# Pi-Control PC-Agent (erste sichere Basis)

Der Helfer ist für **Windows 11 und Linux (einschließlich CachyOS)** ausgelegt. Er benötigt nur Python 3 und für Git-Funktionen eine Git-Installation.

## Aktueller Umfang

- zeigt Betriebssystem, Python-Version, Projektpfad und Git-Verfügbarkeit an;
- zeigt den Git-Status und Änderungen an;
- startet den vorhandenen KI-Speichertest;
- liest Textdateien ausschließlich innerhalb des Projektordners;
- öffnet einen erlaubten Editor, Browser oder Dateimanager;
- öffnet ausdrücklich angegebene HTTP(S)-Adressen.

**Wichtige Grenze:** Dies ist noch kein autonomer KI-Agent. Er verbindet sich noch nicht mit dem Pi-Control-Chat, bearbeitet Dateien nicht selbstständig und steuert Maus/Tastatur nicht. Er führt keine frei eingegebenen Shell-Befehle aus und öffnet keinen Netzwerkserver.

## Start unter Windows 11

1. Python 3 installieren, falls es noch fehlt.
2. Repository herunterladen oder klonen.
3. PowerShell im Projektordner öffnen.
4. `python .\\pc-agent\\agent.py info` ausführen.

## Start unter CachyOS/Linux

1. Python 3 und Git installieren, falls sie noch fehlen.
2. Terminal im Projektordner öffnen.
3. `python3 ./pc-agent/agent.py info` ausführen.

## Beispiele

Windows:
- `python .\\pc-agent\\agent.py status`
- `python .\\pc-agent\\agent.py diff`
- `python .\\pc-agent\\agent.py read docs/AI-MASTER-GEDAECHTNIS.md`
- `python .\\pc-agent\\agent.py tests`

Linux:
- `python3 ./pc-agent/agent.py status`
- `python3 ./pc-agent/agent.py diff`
- `python3 ./pc-agent/agent.py read docs/AI-MASTER-GEDAECHTNIS.md`
- `python3 ./pc-agent/agent.py tests`

Ein anderer Projektordner kann mit `--workspace PFAD` angegeben werden.

## Sicherheitsregeln für die nächsten Ausbaustufen

- Standardmäßig nur den Pi-Control-Projektordner freigeben.
- Dateiänderungen zuerst als Diff anzeigen und vor dem Anwenden bestätigen lassen.
- Keine beliebigen Shell-Befehle von einer KI ausführen.
- Maus/Tastatur-Steuerung nur lokal, sichtbar und auf ausdrückliche Aktion starten.
- Vor Installationen, Admin-Aktionen, Löschen, Neustarts und Netzwerkänderungen extra fragen.
- Keine Passwörter, Tokens oder API-Schlüssel in Git einchecken.
- Erst danach eine lokale, authentifizierte Verbindung zum Pi-Control-Chat entwickeln.


## Lokale API für eine spätere Chat-Verbindung

Die optionale lokale API lauscht ausschließlich auf `127.0.0.1:8765`. Sie ist nicht für die Veröffentlichung über Router, Portweiterleitung, ngrok oder öffentliche Tunnel gedacht.

Start:
- Windows: `python .\\pc-agent\\agent.py serve`
- CachyOS/Linux: `python3 ./pc-agent/agent.py serve`

Beim ersten Start wird ein zufälliges Zugriffstoken unter `~/.pi-control-agent/token` angelegt (Windows: im Benutzerprofil). Das Token niemals in GitHub, Screenshots oder Chatnachrichten veröffentlichen.

Geschützte Endpunkte:
- `GET /v1/status`
- `GET /v1/git/status`
- `GET /v1/git/diff`
- `GET /v1/file?path=...` (nur Dateien im Projektordner, maximal 256 KB)
- `POST /v1/open` mit `{"app":"editor"}`, `browser` oder `file-manager`
- `POST /v1/tests`

Alle Anfragen brauchen `Authorization: Bearer <Token>`. Die Browser-CORS-Freigabe ist auf die veröffentlichte Pi-Control-Dashboard-Origin begrenzt. Andere Origins sind nicht freigegeben. Die API führt keine beliebigen Shell-Befehle aus und bietet keine Datei-Schreib- oder Löschroute.

**Noch nicht verbunden:** Das Dashboard ruft diese API noch nicht auf. Eine sichere Chat-Verbindung erfordert als nächsten Schritt eine UI mit Token-Eingabe und sichtbarer Bestätigung für Aktionen. Desktop-Maus/Tastatur-Automatisierung ist ebenfalls noch nicht implementiert.
