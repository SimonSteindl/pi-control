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

## Neue Aktions-API (noch nicht mit dem Pi-Control-Chat gekoppelt)

Die lokale API unterstützt zusätzlich:
- `POST /v1/file/write`: schreibt eine Textdatei bis 1 MB; bestehende Dateien werden vorher gesichert;
- `POST /v1/file/delete`: verschiebt Dateien/Ordner in den Agent-Papierkorb statt sie endgültig zu löschen;
- `POST /v1/command`: führt eine Argumentliste ohne Shell-Auswertung aus, maximal 120 Sekunden.

**Jede dieser drei Aktionen verlangt `"approved": true`.** Dieses Flag darf ausschließlich aus einer echten Bestätigung im Pi-Control-UI gesetzt werden; es darf niemals automatisch aus einer KI-Antwort übernommen werden. Die UI-/Pi-Backend-Freigabe ist noch nicht integriert, daher sind diese Aktionen noch nicht im Chat verfügbar.

### Optionale private Tailscale-Anbindung

Standardmäßig bleibt die API ausschließlich auf `127.0.0.1:8765`. Eine Netzwerkschnittstelle darf nur ausdrücklich konfiguriert werden und verlangt eine genaue Client-IP-Allowlist. Beispiel (erst verwenden, wenn Pi-Control-Backend und Firewall passend eingerichtet sind):

```bash
python3 ./pc-agent/agent.py serve --bind-host 100.99.171.96 --allowed-client 100.73.19.27
```

Dazu muss die Firewall TCP-Port 8765 ausschließlich für die Tailscale-IP des Raspberry Pi erlauben. **Keinen Router-Port, ngrok oder öffentlichen Tunnel dafür öffnen.** Die tatsächliche Chat-Kopplung und die Bestätigungsdialoge sind noch nicht abgeschlossen.

## Geplante nächste Ausbaustufen

- sichere Verbindung zum Pi-Control-Chat mit ausdrücklicher Geräte-Kopplung;
- Bestätigungsdialoge für Befehle, Dateiänderungen, Löschungen und Systemaktionen;
- Maus-/Tastatursteuerung nur sichtbar und auf ausdrückliche Aktion starten;
- Admin-Aktionen und Installationen nur nach gesonderter Bestätigung.
