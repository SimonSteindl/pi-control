# Pi Control als kostenlose Website

Pi Control läuft direkt im bestehenden Flask-Dienst auf dem Raspberry Pi. Ein
ngrok Agent Endpoint veröffentlicht diesen Dienst unter einer festen
HTTPS-Adresse.

Aktuelle Adresse:

`https://shape-squeegee-unblended.ngrok-free.dev`

Es sind keine Domain, keine Router-Portfreigabe und kein Tailscale-Client auf
dem besuchten Gerät notwendig.

## Aufbau

- Flutter-Webbuild: `/home/stoney22/pi-control/web`
- Flask-Oberfläche und API: `127.0.0.1:8080`
- ngrok-Binary: `/home/stoney22/pi-control/bin/ngrok`
- Autostart: `pi-control-ngrok.service`
- Auth-Datenbank: `/home/stoney22/pi-control/auth.db`
- Dateimanager: ausschließlich `/mnt/pishare` (NAS / USB-Stick), rechtegeschützt
- Web-Terminal: separater Systembenutzer `pi-terminal` ohne sudo

Die öffentliche Website ist durch Benutzername und Passwort geschützt. Das
erste Administratorkonto wird beim ersten Start mit einem zufälligen
Einmal-Passwort erzeugt und muss dieses beim ersten Login ändern. Sitzungen
laufen standardmäßig nach zwölf Stunden ab. Mit „Angemeldet bleiben“ wird eine
Sitzung bis zu 30 Tage in einem `HttpOnly`-/`SameSite`-Cookie gespeichert; das
Passwort selbst wird nie im Cookie abgelegt. Abmelden löscht Cookie und Sitzung.
Administratoren können Konten anlegen, sperren, Passwörter zurücksetzen und
einzelne Rechte vergeben.

Der Dateimanager erlaubt abhängig von den Benutzerrechten Navigation, Upload,
Download, Umbenennen, neue Ordner und das Löschen von Dateien beziehungsweise
leeren Ordnern. System- und Konfigurationsdateien außerhalb des NAS-Speichers
sind nicht erreichbar.

Verfügbare Rechte:

- Dashboard ansehen
- Dateien ansehen
- Dateien hochladen
- Dateien und Ordner verwalten
- Raspberry Pi und Dienste steuern
- CPU-Benchmark starten
- Benutzer verwalten
- Web-Terminal verwenden (ausschließlich Administratoren)

Das Terminal führt einzelne Befehle als abgesicherter Benutzer `pi-terminal`
aus. Befehle sind auf 15 Sekunden und 64 KiB Ausgabe begrenzt. Interaktive
Programme wie `nano`, `vim` oder `htop` sind in dieser Version nicht möglich.

## Aktualisierung

Auf dem Windows-PC:

```powershell
flutter build web --release
scp -r .\build\web stoney22@192.168.0.123:/home/stoney22/pi-control/
scp .\deploy\pi-server\server.py stoney22@192.168.0.123:/home/stoney22/pi-control/server.py
```

Danach auf dem Pi:

```sh
python3 -m py_compile /home/stoney22/pi-control/server.py
sudo systemctl restart pi-control.service
sudo systemctl restart pi-control-ngrok.service
```

## Kontrolle

```sh
systemctl status pi-control.service --no-pager
systemctl status pi-control-ngrok.service --no-pager
curl -I http://127.0.0.1:8080/
```

Der kostenlose ngrok-Tarif zeigt beim ersten Besuch einmalig eine Warnseite und
hat monatliche Nutzungslimits. Für ein persönliches Pi-Dashboard ist das in der
Regel ausreichend.
