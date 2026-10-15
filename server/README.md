# Pi Control Server

Raspberry-Pi-Backend für Pi Control.

## Lokaler Ollama-Chat

Der KI-Chat in der App verwendet den authentifizierten Endpunkt `POST /api/ai/chat`. Der Pi-Control-Server leitet die Anfrage an Ollama weiter, wenn die Umgebungsvariable `PI_CONTROL_OLLAMA_URL` gesetzt ist.

Beispiel für eine private, vom Raspberry Pi erreichbare Ollama-Adresse:

```ini
PI_CONTROL_OLLAMA_URL=http://100.x.y.z:11434
```

Ersetze die Beispieladresse durch die tatsächliche private/VPN-Adresse des CachyOS-PCs. **Ollama nicht direkt ungeschützt ins Internet freigeben.** Für Zugriff von unterwegs zuerst eine private Verbindung (z. B. Tailscale) zwischen Pi und PC einrichten und den Zugriff auf Port 11434 darauf beschränken.

Ohne diese Variable bleibt die KI-Route deaktiviert und liefert `ai_not_configured`. Unterstützte Modelle sind aktuell `qwen3:1.7b` und `qwen3:4b`.


## Dauerhaftes KI-Projektgedächtnis

Der KI-Chat kann Erinnerungen pro angemeldetem Benutzer dauerhaft speichern. Die Daten liegen in `ai_memory.db` im Pi-Control-Basisverzeichnis; die Datei wird mit Berechtigungen `0600` angelegt. Jede Erinnerung ist an die interne Benutzer-ID gebunden, sodass Konten ihre Erinnerungen nicht gegenseitig sehen oder löschen können.

### Im Chat verwenden

- `Merk dir: Die App-Version ist 2.5.0.` speichert die Aussage als Erinnerung.
- Bei späteren Chats lädt Pi-Control AI gespeicherte Erinnerungen automatisch als Kontext.
- Erinnerungen werden nur gespeichert, wenn der Benutzer ausdrücklich darum bittet.
- Passwörter, API-Schlüssel und andere erkennbare Geheimnisse werden abgewiesen.
- Der Speicher ist auf 100 Erinnerungen pro Konto begrenzt; ältere Erinnerungen werden bei Bedarf entfernt.

### Erinnerungen verwalten

Die authentifizierten Endpunkte sind:

- `GET /api/ai/memory` – Erinnerungen des angemeldeten Kontos auflisten.
- `POST /api/ai/memory` mit JSON `{"memory":"..."}` – eine Erinnerung speichern.
- `DELETE /api/ai/memory/<id>` – eine Erinnerung dieses Kontos löschen.

Die KI erhält Projektgrundwissen über die App und den Flask-Server sowie die gespeicherten Erinnerungen. Sie hat dadurch **keinen automatischen Zugriff auf Live-Daten oder Dateien** des Raspberry Pi und darf solche Zugriffe nicht behaupten.
