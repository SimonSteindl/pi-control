#!/usr/bin/env bash
set -euo pipefail

target=/home/stoney22/pi-control
resolved_target="$(readlink -f "$target")"
if [[ "$resolved_target" != "/home/stoney22/pi-control" ]]; then
  echo "Unexpected deployment target: $resolved_target" >&2
  exit 1
fi

stamp="$(date +%Y%m%d-%H%M%S)"
backup="$target/backups/$stamp"

sudo mkdir -p "$backup"
sudo cp -a "$target/server.py" "$backup/server.py"
if [[ -f "$target/auth.db" ]]; then
  sudo cp -a "$target/auth.db" "$backup/auth.db"
fi
sudo mv "$target/web" "$backup/web"
sudo mv /tmp/pi-control-web-new "$target/web"
sudo install -m 0644 /tmp/server.py "$target/server.py"
sudo chown -R root:root "$target/web" "$target/server.py"
sudo systemctl restart pi-control
sleep 2
systemctl is-active pi-control
curl -fsS http://127.0.0.1:8080/api/auth/status
echo
echo "BACKUP=$backup"
