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
