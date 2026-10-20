# Pi-Control PC-Agent

Der Helfer ist für **Windows 11 und Linux (einschließlich CachyOS)** ausgelegt. Er benötigt Python 3; für Git-Funktionen zusätzlich Git.

## Aktueller Umfang

- zeigt System-, Projekt- und Git-Status und liest freigegebene Textdateien;
- listet Ordner im freigegebenen Benutzerverzeichnis und startet den KI-Speichertest;
- öffnet erlaubte Apps und HTTP(S)-Adressen;
- unterstützt im Pi-Control-AI-Chat bestätigungspflichtige PC-Aktionen;
- schreibt Dateien mit Sicherung vorhandener Dateien, verschiebt Löschungen in einen Agent-Papierkorb und führt Befehle als Argumentliste ohne Shell-Auswertung aus.

**Noch nicht enthalten:** automatische Umwandlung beliebiger natürlicher Sprache in einen Plan, sichtbare Maus-/Tastatursteuerung und Administrator-/Root-Aktionen. Dateiänderungen, Löschungen und Befehle werden erst nach ausdrücklicher Bestätigung im Pi-Control-UI ausgeführt.

## Start

Im Projektordner:

- Windows: `python .\\pc-agent\\agent.py info`
- CachyOS/Linux: `python3 ./pc-agent/agent.py info`

Die lokale API kann mit `python3 ./pc-agent/agent.py serve` (Linux) beziehungsweise `python .\\pc-agent\\agent.py serve` (Windows) gestartet werden.

## Lokale API

Die API lauscht ausschließlich auf `127.0.0.1:8765`; **nicht** per Router-Portweiterleitung, ngrok oder öffentlichem Tunnel freigeben. Beim ersten Start wird ein zufälliges Token unter `~/.pi-control-agent/token` angelegt. Das Token niemals teilen oder einchecken.

Geschützte Endpunkte:

- `GET /v1/status`
- `GET /v1/git/status`
- `GET /v1/git/diff`
- `GET /v1/file?path=...` – Textdatei bis 1 MB lesen
- `GET /v1/files?path=...` – direkten Ordnerinhalt auflisten
- `POST /v1/open` – nur erlaubte Programme
- `POST /v1/tests` – vorhandenen Speichertest starten
- `POST /v1/agent/run` – einen validierten Plan mit 1–8 sicheren Schritten ausführen und im Gedächtnis protokollieren. Beispiel-Body: `{"title":"Projekt prüfen","goal":"Status und README kontrollieren","steps":[{"action":"git_status"},{"action":"read_file","path":"README.md"}]}`. Erlaubt sind nur `status`, `git_status`, `git_diff`, `read_file`, `list_files` und `tests`.

Alle Anfragen benötigen `Authorization: Bearer <Token>`. Der Plan-Endpunkt akzeptiert keine Shell-Befehle, Dateiänderungen, Löschungen oder App-Starts; diese bleiben außerhalb des automatischen Planläufers und benötigen weiterhin gesonderte Freigabe.

## Dateizugriff und Schutz

Standardmäßig darf die API innerhalb des **Benutzerordners** (`~`) lesen und Ordner auflisten. Relative Pfade beziehen sich auf diesen Ordner; absolute Pfade sind nur erlaubt, wenn sie darin liegen. Symlinks, die nach außerhalb führen, werden durch die Pfadauflösung nicht als Zugriff außerhalb zugelassen.

Bekannte Credential-Bereiche und -Dateitypen sind standardmäßig gesperrt, darunter `.ssh`, `.gnupg`, `.pki`, `.password-store`, Keyrings, `.env`, `.netrc`, Dateien namens `credentials` oder `token` sowie private Schlüsseldateien wie `.pem`, `.key`, `.p12` und `.pfx`. Das ist eine Schutzschicht, keine vollständige Erkennung aller möglichen Geheimnisse. Vor dem Teilen von Ausgaben weiterhin prüfen, dass sie keine privaten Daten enthalten.

Den freigegebenen Stammordner kann man beim direkten Start von `local_api.py` mit `--access-root PFAD` ändern. Die API bleibt lokal und token-geschützt.

## Aktions-API mit Bestätigung (Chat-Integration im Code, noch nicht auf Geräten aktiviert)

Die lokale API unterstützt zusätzlich:
- `POST /v1/file/write`: schreibt eine Textdatei bis 1 MB; bestehende Dateien werden vorher gesichert;
- `POST /v1/file/delete`: verschiebt Dateien/Ordner in den Agent-Papierkorb statt sie endgültig zu löschen;
- `POST /v1/command`: führt eine Argumentliste ohne Shell-Auswertung aus, maximal 120 Sekunden.

**Jede dieser drei Aktionen verlangt `"approved": true`.** Dieses Flag darf ausschließlich aus einer echten Bestätigung im Pi-Control-UI gesetzt werden; es darf niemals automatisch aus einer KI-Antwort übernommen werden. Die Chat- und Backend-Routen sind in diesem Branch vorbereitet, müssen aber erst auf dem Pi aktualisiert und mit dem Agenten gekoppelt werden.

### Optionale private Tailscale-Anbindung

Standardmäßig bleibt die API ausschließlich auf `127.0.0.1:8765`. Eine Netzwerkschnittstelle darf nur ausdrücklich konfiguriert werden und verlangt eine genaue Client-IP-Allowlist. Beispiel (erst verwenden, wenn der Branch auf dem PC aktualisiert wurde und Pi-Control-Backend/Firewall passend eingerichtet sind):

```bash
python3 ./pc-agent/agent.py serve --bind-host 100.99.171.96 --allowed-client 100.73.19.27
```

Dazu muss die Firewall TCP-Port 8765 ausschließlich für die Tailscale-IP des Raspberry Pi erlauben. Auf dem Pi müssen `PI_CONTROL_PC_AGENT_URL=http://100.99.171.96:8765` und `PI_CONTROL_PC_AGENT_TOKEN` gesetzt sein; der Token ist der Inhalt von `~/.pi-control-agent/token` auf dem PC und darf nicht in den Chat oder ins GitHub-Repository kopiert werden. **Keinen Router-Port, ngrok oder öffentlichen Tunnel dafür öffnen.** Der Chat schlägt Aktionen vor, zeigt eine Bestätigung an und führt erst nach Klick auf „Bestätigen & ausführen“ aus. GUI-Maus-/Tastatursteuerung und Administratoraktionen sind noch nicht enthalten.

## Geplante nächste Ausbaustufen

- sichere Verbindung zum Pi-Control-Chat mit ausdrücklicher Geräte-Kopplung;
- Bestätigungsdialoge für Befehle, Dateiänderungen, Löschungen und Systemaktionen;
- Maus-/Tastatursteuerung nur sichtbar und auf ausdrückliche Aktion starten;
- Admin-Aktionen und Installationen nur nach gesonderter Bestätigung.
