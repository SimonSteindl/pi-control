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
maintenance_flag="$target/maintenance.enabled"

sudo install -o root -g root -m 0644 /tmp/maintenance.html "$target/maintenance.html"
sudo touch "$maintenance_flag"
cleanup_maintenance() {
  sudo rm -f "$maintenance_flag"
}
trap cleanup_maintenance EXIT

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
systemctl is-active pi-control

maintenance_ready=false
for _attempt in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:8080/api/maintenance; then
    echo
    maintenance_ready=true
    break
  fi
  sleep 1
done
if [[ "$maintenance_ready" != true ]]; then
  echo "Pi Control did not become ready within 30 seconds" >&2
  exit 1
fi

cleanup_maintenance
trap - EXIT
curl -fsS http://127.0.0.1:8080/api/auth/status
echo
rm -f /tmp/pi-control-web-deploy.tgz
echo "BACKUP=$backup"
