#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 /mnt/pishare/Backups/Pi-Control/pi-control-YYYYMMDD-HHMMSS.tar.gz" >&2
    exit 2
fi

base_dir=/home/stoney22/pi-control
backup_dir=/mnt/pishare/Backups/Pi-Control
archive="$(readlink -f "$1")"

case "$archive" in
    "$backup_dir"/pi-control-*.tar.gz) ;;
    *) echo "Backup archive must be inside $backup_dir" >&2; exit 2 ;;
esac

test -f "$archive"
temporary_dir="$(mktemp -d /tmp/pi-control-restore-XXXXXX)"
trap 'rm -rf "$temporary_dir"' EXIT
tar -xzf "$archive" -C "$temporary_dir"
test -f "$temporary_dir/auth.db"

systemctl stop pi-control
cp -a "$base_dir/auth.db" "$base_dir/auth.db.before-restore-$(date +%Y%m%d-%H%M%S)"
install -o root -g root -m 0600 "$temporary_dir/auth.db" "$base_dir/auth.db"
for file_name in history.json benchmark.json benchmark_history.json; do
    if [[ -f "$temporary_dir/$file_name" ]]; then
        install -o root -g root -m 0644 "$temporary_dir/$file_name" "$base_dir/$file_name"
    fi
done
systemctl start pi-control
systemctl is-active --quiet pi-control
echo "Backup restored: $archive"
