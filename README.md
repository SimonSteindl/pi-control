# Pi Control

Pi Control ist ein Projekt zur **Überwachung und Verwaltung eines Raspberry Pi** über eine eigene App.

Das Repository besteht bewusst aus zwei Hauptbereichen:

- `app/` – Mobile App
- `server/` – Raspberry-Pi-Server

## 📁 Projektstruktur

```text
pi-control/
├── app/
├── server/
└── README.md
```

## 📱 App

Die App ist die Benutzeroberfläche von Pi Control.

Sie kommuniziert mit dem Pi-Control-Server und kann Informationen des Raspberry Pi anzeigen.

Geplante bzw. unterstützte Informationen können unter anderem sein:

- 🌡️ CPU-Temperatur
- 💾 Speicherplatz
- 🗄️ angeschlossener Speicher
- 🧠 RAM-Auslastung
- ⏱️ Uptime
- 🌐 Netzwerk-/IP-Informationen
- ⚠️ Warnungen bei Problemen

Die App befindet sich in `app/`.

## 🖥️ Server

Der Server läuft direkt auf dem Raspberry Pi.

Er sammelt Systeminformationen und stellt diese über eine API für die App bereit.

Der Server befindet sich in `server/`.

Der Server basiert auf **Python/Flask**.

## 🔄 Kommunikation

Die grundlegende Kommunikation sieht so aus:

```text
┌──────────────┐
│   Pi Control │
│      App     │
└──────┬───────┘
       │ HTTP / API
       ▼
┌──────────────┐
│ Pi Control   │
│    Server    │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Raspberry Pi │
│ Systemdaten  │
└──────────────┘
```

Die App ruft die API des Servers auf und erhält die aktuellen Informationen des Raspberry Pi.

## ⚙️ Server

Der Server ist dafür gedacht, dauerhaft auf dem Raspberry Pi zu laufen.

Wenn der Server über systemd eingerichtet ist, kann sein Status beispielsweise mit folgendem Befehl geprüft werden:

```bash
sudo systemctl status pi-control
```

Neustart nach Änderungen:

```bash
sudo systemctl restart pi-control
```

## 🤖 Hinweise für KI / Coding Agents

Dieses Repository enthält **nur die beiden Projektbereiche `app/` und `server/`**.

### Regeln

- Änderungen an der App gehören nach `app/`.
- Änderungen am Raspberry-Pi-Server gehören nach `server/`.
- Keine unnötigen zusätzlichen Projekte oder Ordner erstellen.
- Bestehende Funktionen nicht ohne Grund entfernen.
- Die Kommunikation zwischen App und Server muss bei Änderungen berücksichtigt werden.
- Vorhandene API-Strukturen möglichst kompatibel halten.
- Bei Serveränderungen berücksichtigen, dass der Code direkt auf einem Raspberry Pi läuft.
- Keine Passwörter, API-Keys oder andere Geheimnisse in das Repository committen.
- Vor größeren Änderungen zuerst die vorhandene Struktur und den bestehenden Code prüfen.

## 🚧 Entwicklungsstatus

Pi Control befindet sich in aktiver Entwicklung.

Funktionen und die Benutzeroberfläche können sich noch ändern und erweitert werden.

## 🎯 Ziel

Das Ziel von Pi Control ist eine einfache und übersichtliche Möglichkeit, einen Raspberry Pi über eine eigene App zu überwachen und zu verwalten.

---

**Pi Control – Raspberry Pi monitoring and control made simple.**
