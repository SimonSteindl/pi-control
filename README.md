# Pi Control

Pi Control bietet neben Dashboard und Dateimanager einen integrierten WebDAV-Zugang unter `/webdav/`. Er verwendet dieselben Benutzerkonten, Ordnerzuweisungen, Berechtigungen und Speicherlimits wie die Weboberfläche.

Pi Control is a self-hosted Flutter dashboard and private cloud for Raspberry
Pi. It combines system monitoring, file management, users and storage quotas,
backups, a web terminal, media tools, OCR, encrypted vaults, Docker management,
scheduled tasks, and secure remote access in one responsive app.

The flight-weather tab shows worldwide METAR and TAF reports by ICAO code,
including a direct link to the matching metar-taf.com detail page.

## Install

- Web app: open your Pi Control HTTPS address in a browser. On iPhone or iPad,
  use **Share → Add to Home Screen → Open as Web App**.
- Android: download the current APK from the `App/.apk` directory exposed by
  your own Pi Control server.
- Server: see [`deploy/README.md`](deploy/README.md).

## Privacy

Pi Control has no central cloud, advertising, or analytics. It connects to the
Raspberry Pi selected by the user. See [`PRIVACY.md`](PRIVACY.md).

## Building

```bash
flutter pub get
flutter analyze
flutter build apk --release
flutter build web --release
```

## License

Copyright 2026 Simon Steindl. Licensed under the
[Apache License 2.0](LICENSE).
