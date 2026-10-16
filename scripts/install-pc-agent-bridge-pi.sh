#!/usr/bin/env bash
set -euo pipefail

EXPECTED_ROOT="/home/stoney22/pi-control"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE="pi-control.service"
BRIDGE_ENV="/etc/pi-control/pc-agent-bridge.env"
DROPIN_DIR="/etc/systemd/system/pi-control.service.d"
DROPIN="$DROPIN_DIR/pc-agent-bridge.conf"

if [[ "$EUID" -ne 0 ]]; then
  echo "Bitte mit sudo starten: sudo bash $REPO_ROOT/scripts/install-pc-agent-bridge-pi.sh" >&2
  exit 2
fi
if [[ "$REPO_ROOT" != "$EXPECTED_ROOT" ]]; then
  echo "Unerwarteter Projektpfad: $REPO_ROOT (erwartet $EXPECTED_ROOT)" >&2
  exit 2
fi
if [[ "$(git -C "$REPO_ROOT" branch --show-current)" != "feature/pc-agent-bridge-mvp" ]]; then
  echo "Bitte zuerst den Branch feature/pc-agent-bridge-mvp auschecken." >&2
  exit 2
fi
if [[ ! -f "$REPO_ROOT/server/server.py" || ! -f "$REPO_ROOT/server/pc_agent_bridge.py" ]]; then
  echo "Serverdateien fehlen; es wurde nichts geändert." >&2
  exit 2
fi
if ! systemctl cat "$SERVICE" >/dev/null 2>&1; then
  echo "systemd-Dienst $SERVICE wurde nicht gefunden." >&2
  exit 2
fi
if ! python3 - "$REPO_ROOT/server/server.py" "$REPO_ROOT/server/pc_agent_bridge.py" <<'PY'
import ast
import pathlib
import sys
for filename in sys.argv[1:]:
    ast.parse(pathlib.Path(filename).read_text(encoding="utf-8"), filename=filename)
PY
then
  echo "Python-Syntaxprüfung fehlgeschlagen; es wurde nichts geändert." >&2
  exit 2
fi

echo "Dieses Skript erstellt ein systemd-Token und startet Pi-Control neu."
echo "Der PC-Agent bleibt lokal; nur ausgehende HTTPS-Verbindungen werden verwendet."
read -r -p "Fortfahren und pi-control.service neu starten? [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Abgebrochen; es wurde nichts geändert."
  exit 0
fi

CURRENT_EXEC="$(systemctl show -p ExecStart --value "$SERVICE")"
CURRENT_WD="$(systemctl show -p WorkingDirectory --value "$SERVICE")"
NEED_EXEC_OVERRIDE=0
if [[ "$CURRENT_EXEC" != *"$REPO_ROOT/server/server.py"* ]]; then
  NEED_EXEC_OVERRIDE=1
fi
NEED_WD_OVERRIDE=0
if [[ -n "$CURRENT_WD" && ! -d "$CURRENT_WD" ]]; then
  NEED_WD_OVERRIDE=1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="/var/backups/pi-control-pc-agent-$STAMP"
mkdir -p "$BACKUP_DIR"
if [[ -f "$BRIDGE_ENV" ]]; then cp -a "$BRIDGE_ENV" "$BACKUP_DIR/pc-agent-bridge.env"; fi
if [[ -f "$DROPIN" ]]; then cp -a "$DROPIN" "$BACKUP_DIR/pc-agent-bridge.conf"; fi

mkdir -p /etc/pi-control "$DROPIN_DIR"
TOKEN=""
if [[ -f "$BRIDGE_ENV" ]]; then
  TOKEN="$(sed -n 's/^PI_CONTROL_PC_AGENT_TOKEN=//p' "$BRIDGE_ENV" | head -n 1)"
fi
if [[ ${#TOKEN} -lt 40 ]]; then
  TOKEN="$(python3 -c 'import secrets; print(secrets.token_urlsafe(48))')"
fi
printf 'PI_CONTROL_PC_AGENT_TOKEN=%s\n' "$TOKEN" > "$BRIDGE_ENV"
chmod 600 "$BRIDGE_ENV"
chown root:root "$BRIDGE_ENV"

{
  echo "[Service]"
  echo "EnvironmentFile=$BRIDGE_ENV"
  if [[ "$NEED_WD_OVERRIDE" -eq 1 || "$NEED_EXEC_OVERRIDE" -eq 1 ]]; then
    echo "WorkingDirectory=$REPO_ROOT"
  fi
  if [[ "$NEED_EXEC_OVERRIDE" -eq 1 ]]; then
    echo "ExecStart="
    echo "ExecStart=/usr/bin/python3 $REPO_ROOT/server/server.py"
  fi
} > "$DROPIN"
chmod 644 "$DROPIN"

systemctl daemon-reload
if ! systemctl restart "$SERVICE"; then
  echo "Neustart fehlgeschlagen. Stelle die vorherige Bridge-Konfiguration wieder her." >&2
  if [[ -f "$BACKUP_DIR/pc-agent-bridge.conf" ]]; then
    cp -a "$BACKUP_DIR/pc-agent-bridge.conf" "$DROPIN"
  else
    rm -f "$DROPIN"
  fi
  if [[ -f "$BACKUP_DIR/pc-agent-bridge.env" ]]; then
    cp -a "$BACKUP_DIR/pc-agent-bridge.env" "$BRIDGE_ENV"
  else
    rm -f "$BRIDGE_ENV"
  fi
  systemctl daemon-reload || true
  systemctl restart "$SERVICE" || true
  journalctl -u "$SERVICE" -n 30 --no-pager || true
  exit 1
fi

if ! systemctl is-active --quiet "$SERVICE"; then
  echo "Der Dienst ist nach dem Neustart nicht aktiv. Prüfe journalctl -u $SERVICE." >&2
  journalctl -u "$SERVICE" -n 30 --no-pager || true
  exit 1
fi

echo
echo "Pi-Control läuft. Das gemeinsame Token muss jetzt am PC in start-bridge.sh eingegeben werden:"
echo "$TOKEN"
echo
echo "Token nicht in GitHub einchecken und niemandem schicken. Backup: $BACKUP_DIR"
