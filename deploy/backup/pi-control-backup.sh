#!/usr/bin/env bash
set -euo pipefail

base_dir=/home/stoney22/pi-control
backup_dir=/mnt/pishare/Backups/Pi-Control
auth_db="$base_dir/auth.db"

test "$(readlink -f "$base_dir")" = /home/stoney22/pi-control
mkdir -p "$backup_dir"
test "$(readlink -f "$backup_dir")" = /mnt/pishare/Backups/Pi-Control

stamp="$(date +%Y%m%d-%H%M%S)"
archive_name="pi-control-$stamp.tar.gz"
temporary_dir="$(mktemp -d /tmp/pi-control-backup-XXXXXX)"
trap 'rm -rf "$temporary_dir"' EXIT

python3 - "$auth_db" "$temporary_dir/auth.db" <<'PY'
import sqlite3
import sys

source = sqlite3.connect(sys.argv[1])
destination = sqlite3.connect(sys.argv[2])
with destination:
    source.backup(destination)
destination.close()
source.close()
PY

for file_name in history.json benchmark.json benchmark_history.json; do
    if [[ -f "$base_dir/$file_name" ]]; then
        cp -a "$base_dir/$file_name" "$temporary_dir/$file_name"
    fi
done

printf 'Pi Control configuration backup\nCreated: %s\n' "$(date --iso-8601=seconds)" > "$temporary_dir/README.txt"
tar -czf "$backup_dir/$archive_name" -C "$temporary_dir" .
chmod 0600 "$backup_dir/$archive_name"

find "$backup_dir" -maxdepth 1 -type f -name 'pi-control-*.tar.gz' -mtime +14 -delete
printf '%s\n' "$archive_name"
