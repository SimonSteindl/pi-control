# Pi-Control PC-Agent

Der Helfer ist für **Windows 11 und Linux (einschließlich CachyOS)** ausgelegt. Er benötigt Python 3; für Git-Funktionen zusätzlich Git.

## Aktueller Umfang

- zeigt System-, Projekt- und Git-Status;
- liest Textdateien und listet Ordner im freigegebenen Benutzerverzeichnis;
- startet den vorhandenen KI-Speichertest;
- öffnet erlaubte Apps und HTTP(S)-Adressen.

**Noch nicht enthalten:** Verbindung zum Pi-Control-Chat, Dateiänderungen, Löschaktionen oder Maus-/Tastatursteuerung. Der Agent führt keine frei eingegebenen Shell-Befehle aus.

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

Alle Anfragen benötigen `Authorization: Bearer <Token>`.

## Dateizugriff und Schutz

Standardmäßig darf die API innerhalb des **Benutzerordners** (`~`) lesen und Ordner auflisten. Relative Pfade beziehen sich auf diesen Ordner; absolute Pfade sind nur erlaubt, wenn sie darin liegen. Symlinks, die nach außerhalb führen, werden durch die Pfadauflösung nicht als Zugriff außerhalb zugelassen.

Bekannte Credential-Bereiche und -Dateitypen sind standardmäßig gesperrt, darunter `.ssh`, `.gnupg`, `.pki`, `.password-store`, Keyrings, `.env`, `.netrc`, Dateien namens `credentials` oder `token` sowie private Schlüsseldateien wie `.pem`, `.key`, `.p12` und `.pfx`. Das ist eine Schutzschicht, keine vollständige Erkennung aller möglichen Geheimnisse. Vor dem Teilen von Ausgaben weiterhin prüfen, dass sie keine privaten Daten enthalten.

Den freigegebenen Stammordner kann man beim direkten Start von `local_api.py` mit `--access-root PFAD` ändern. Die API bleibt lokal und token-geschützt.

## Nächste Ausbaustufen

- sichere Verbindung zum Pi-Control-Chat mit ausdrücklicher Geräte-Kopplung;
- Dateiänderungen als Diff vorschlagen und erst nach Bestätigung anwenden;
- Maus-/Tastatursteuerung nur lokal, sichtbar und auf ausdrückliche Aktion starten;
- keine Admin-Aktionen, Installationen oder Löschungen ohne gesonderte Bestätigung.
