#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_ROOT="$HOME/pi-control"
PYTHON="${PYTHON:-python3}"
DEFAULT_SERVER_URL="https://shape-squeegee-unblended.ngrok-free.dev"

if [[ "$REPO_ROOT" != "$EXPECTED_ROOT" ]]; then
  echo "Bitte das Projekt zuerst nach ~/pi-control legen. Gefunden: $REPO_ROOT" >&2
  exit 2
fi
command -v "$PYTHON" >/dev/null 2>&1 || { echo "Python 3 wurde nicht gefunden." >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "curl wurde nicht gefunden." >&2; exit 2; }

read -r -p "Pi-Control HTTPS-URL [$DEFAULT_SERVER_URL]: " entered_url
PI_CONTROL_SERVER_URL="${entered_url:-$DEFAULT_SERVER_URL}"
if [[ "$PI_CONTROL_SERVER_URL" != https://* ]]; then
  echo "Aus Sicherheitsgründen wird nur eine HTTPS-URL akzeptiert." >&2
  exit 2
fi
read -r -s -p "Gemeinsames PC-Agent-Token (wird nicht angezeigt): " PI_CONTROL_PC_AGENT_TOKEN
echo
if [[ ${#PI_CONTROL_PC_AGENT_TOKEN} -lt 40 ]]; then
  echo "Das Token ist zu kurz. Erzeuge auf dem Pi ein zufälliges Token mit mindestens 40 Zeichen." >&2
  exit 2
fi

mkdir -p "$HOME/.pi-control-agent"
API_STATUS="$(curl -sS --max-time 1 -o /dev/null -w '%{http_code}' http://127.0.0.1:8765/v1/status 2>/dev/null || true)"
if [[ "$API_STATUS" != "401" && "$API_STATUS" != "200" ]]; then
  nohup "$PYTHON" -u "$REPO_ROOT/pc-agent/local_api.py" --workspace "$REPO_ROOT" --access-root "$HOME" >"$HOME/.pi-control-agent/local-api.log" 2>&1 </dev/null &
  for _ in {1..10}; do
    sleep 1
    API_STATUS="$(curl -sS --max-time 1 -o /dev/null -w '%{http_code}' http://127.0.0.1:8765/v1/status 2>/dev/null || true)"
    [[ "$API_STATUS" == "401" || "$API_STATUS" == "200" ]] && break
  done
fi
if [[ "$API_STATUS" != "401" && "$API_STATUS" != "200" ]]; then
  echo "Lokale PC-Agent-API konnte nicht gestartet werden. Siehe ~/.pi-control-agent/local-api.log" >&2
  exit 1
fi

export PI_CONTROL_SERVER_URL PI_CONTROL_PC_AGENT_TOKEN
echo "Lokale API bereit. Die Bridge fragt den Pi ab; nur list_files/read_file sind erlaubt."
exec "$PYTHON" "$REPO_ROOT/pc-agent/bridge_client.py"
