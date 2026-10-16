# Pi-Control

**Pi-Control** is an open-source, self-hosted dashboard for monitoring and managing a Raspberry Pi through a Flutter app and browser interface.

- **Public website:** https://pi-control-public.steindlsimon12.workers.dev/
- **Source code:** https://github.com/SimonSteindl/pi-control
- **Downloads:** https://github.com/SimonSteindl/pi-control/releases
- **Issues and feature requests:** https://github.com/SimonSteindl/pi-control/issues

> Pi-Control is actively developed. Check the current release notes and setup instructions before updating a running Raspberry Pi.

## What it includes

- System overview: CPU temperature, uptime, memory, storage and network information.
- Resource history and CPU benchmark information.
- File manager for connected storage, with supported previews and permission-controlled actions.
- Backup tools and media selection workflows.
- Aviation weather lookup for METAR/TAF by ICAO code.
- Account/session management and permission-aware admin tools.
- Optional AI chat and saved memories when the server's AI configuration is available.
- Android app and browser-based dashboard.

Features depend on the Raspberry Pi hardware, enabled server modules, account permissions and configuration.

## Project structure

```text
pi-control/
├── app/                    # Flutter app (Android and web build)
├── server/
│   ├── server.py           # Python/Flask API
│   ├── public-site/        # Public product landing page
│   └── dashboard-worker/   # Cloudflare static dashboard worker
├── .github/workflows/      # Build, test and publishing automation
└── README.md
```

## Architecture

```text
Flutter app / browser
        │
        │ authenticated API requests
        ▼
Python + Flask on your Raspberry Pi
        │
        ├── System and storage information
        ├── Account and permission checks
        ├── File and backup features
        └── Optional configured AI service
```

The public landing page is separate from the private dashboard and does not need access to your device API.

## Requirements

- A compatible Raspberry Pi or Linux host supported by the server code.
- Python 3 and the Python dependencies used by the server.
- Flutter SDK matching the app's configured SDK constraints when building locally.
- Android or a modern browser for the client.
- Network access between the client and the server, or a deliberately configured secure remote-access method.

Review the current source and release notes for exact setup requirements. Do not assume a fresh install and an existing installation use identical paths or service settings.

## Development and checks

### Flutter app

From the repository root:

```bash
cd app
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --release
```

The GitHub Actions workflow runs static analysis and builds a release APK. Pull-request builds are for validation; published downloads are listed on the Releases page.

### Public website

The static site is in `server/public-site/`. Run its dependency-free quality checks from the repository root:

```bash
python3 server/public-site/test_site.py
```

The check validates essential metadata, navigation anchors, canonical URL, sitemap, robots.txt and key project links.

### Raspberry Pi server

The server entry point is `server/server.py`. If you already have a working installation, back up your configuration and review the exact diff before switching branches or restarting services.

Typical service checks (when installed as a systemd unit):

```bash
sudo systemctl status pi-control.service
sudo journalctl -u pi-control.service -n 100 --no-pager
```

Use the service name and paths actually configured on your device.

## Security notes

- Never commit passwords, session tokens, private keys, API credentials or personal backups.
- Use HTTPS for remote access. Do not expose a development API or loopback-only local agent directly to the internet.
- Keep the Pi-Control server and operating system updated.
- Give each account only the permissions it needs.
- Before using an experimental feature or branch on your daily server, read its limitations and test it separately where possible.

## Contribution guidelines

- Preserve existing API behavior unless a change is deliberate and documented.
- Keep Flutter code in `app/` and Raspberry Pi API code in `server/`.
- Add or update automated checks when changing behavior.
- Test on the supported runtime; CI success alone does not prove a feature works on every Raspberry Pi model.
- Explain configuration changes and rollback steps.
- Keep secrets out of commits, issue reports and screenshots.

## Project status

Pi-Control is under active development. Some optional features need extra server configuration, and changes may be released as prerelease builds before they are considered stable.

**Pi-Control — your Raspberry Pi, at a glance.**
