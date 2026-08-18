#!/usr/bin/env python3

import hashlib
import json
import os
import platform
import secrets
import select
import signal
import shutil
import socket
import sqlite3
import subprocess
import threading
import time
import urllib.request
from functools import wraps
from pathlib import Path

from flask import Flask, g, jsonify, request, send_file, send_from_directory
from werkzeug.security import check_password_hash, generate_password_hash

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 256 * 1024 * 1024

PORT = 8080
USB_PATH = "/mnt/pishare"

# Dein ntfy-Topic. Leer setzen ("") = Push-Warnungen deaktivieren.
NTFY_TOPIC = "Stoney22"

BASE_DIR = Path("/home/stoney22/pi-control")
WEB_DIR = BASE_DIR / "web"
HISTORY_FILE = BASE_DIR / "history.json"
BENCHMARK_FILE = BASE_DIR / "benchmark.json"
BENCHMARK_HISTORY_FILE = BASE_DIR / "benchmark_history.json"
AUTH_DB_FILE = BASE_DIR / "auth.db"
INITIAL_ADMIN_FILE = BASE_DIR / "initial_admin.json"
BACKUP_DIRECTORY = Path(USB_PATH) / "Backups" / "Pi-Control"
BACKUP_SCRIPT = BASE_DIR / "backup.sh"
APP_VERSION = "1.5.0"

HISTORY_INTERVAL_SECONDS = 60
HISTORY_MAX_POINTS = 24 * 60

BENCHMARK_DURATION_SECONDS = 5.0
BENCHMARK_COOLDOWN_SECONDS = 30

history_lock = threading.Lock()
history_points = []

alert_lock = threading.Lock()
last_alert_states = {}

benchmark_lock = threading.Lock()
benchmark_data = {}
benchmark_history = []
last_benchmark_finished = 0.0

BENCHMARK_HISTORY_MAX_POINTS = 50

FILE_ROOT = Path(USB_PATH)
FILE_OWNER_USER = "stoney22"
file_operation_lock = threading.Lock()
download_token_lock = threading.Lock()
download_tokens = {}
DOWNLOAD_TOKEN_LIFETIME_SECONDS = 60
SHARE_LINK_LIFETIME_SECONDS = 7 * 24 * 60 * 60
TRASH_DIRECTORY_NAME = ".pi-control-trash"
SEARCH_RESULT_LIMIT = 100
SEARCH_VISIT_LIMIT = 25000

SESSION_LIFETIME_SECONDS = 12 * 60 * 60
REMEMBER_SESSION_LIFETIME_SECONDS = 30 * 24 * 60 * 60
SESSION_COOKIE_NAME = "pi_control_session"
PASSWORD_MIN_LENGTH = 10
PERMISSION_DEFINITIONS = {
    "dashboard_view": "Dashboard ansehen",
    "files_view": "Dateien ansehen",
    "files_upload": "Dateien hochladen",
    "files_manage": "Dateien und Ordner verwalten",
    "system_control": "Raspberry Pi und Dienste steuern",
    "benchmark_run": "CPU-Benchmark starten",
    "users_manage": "Benutzer verwalten",
    "terminal_access": "Administratives Web-Terminal verwenden",
}
ALL_PERMISSIONS = set(PERMISSION_DEFINITIONS)
ADMIN_ONLY_PERMISSIONS = {"terminal_access"}
ASSIGNABLE_PERMISSIONS = ALL_PERMISSIONS - ADMIN_ONLY_PERMISSIONS

TERMINAL_USER = "pi-terminal"
TERMINAL_HOME = Path("/home/pi-terminal")
TERMINAL_TIMEOUT_SECONDS = 15
TERMINAL_MAX_COMMAND_LENGTH = 2000
TERMINAL_MAX_OUTPUT_BYTES = 64 * 1024
terminal_slot = threading.BoundedSemaphore(1)

login_attempt_lock = threading.Lock()
login_attempts = {}
LOGIN_WINDOW_SECONDS = 5 * 60
LOGIN_MAX_ATTEMPTS = 8


def auth_connection():
    connection = sqlite3.connect(AUTH_DB_FILE, timeout=10)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    return connection


def initialize_auth_database():
    BASE_DIR.mkdir(parents=True, exist_ok=True)

    with auth_connection() as connection:
        connection.executescript("""
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT NOT NULL COLLATE NOCASE UNIQUE,
                display_name TEXT NOT NULL,
                password_hash TEXT NOT NULL,
                is_admin INTEGER NOT NULL DEFAULT 0,
                permissions TEXT NOT NULL DEFAULT '[]',
                storage_path TEXT NOT NULL DEFAULT '',
                storage_quota_bytes INTEGER,
                is_active INTEGER NOT NULL DEFAULT 1,
                must_change_password INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS sessions (
                token_hash TEXT PRIMARY KEY,
                user_id INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                expires_at INTEGER NOT NULL,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS sessions_user_id
            ON sessions(user_id);

            CREATE INDEX IF NOT EXISTS sessions_expires_at
            ON sessions(expires_at);

            CREATE TABLE IF NOT EXISTS trash_items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                root_path TEXT NOT NULL,
                trash_name TEXT NOT NULL,
                original_path TEXT NOT NULL,
                display_name TEXT NOT NULL,
                is_directory INTEGER NOT NULL DEFAULT 0,
                deleted_at INTEGER NOT NULL,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS trash_items_user_id
            ON trash_items(user_id);

            CREATE TABLE IF NOT EXISTS file_shares (
                token_hash TEXT PRIMARY KEY,
                user_id INTEGER NOT NULL,
                root_path TEXT NOT NULL,
                relative_path TEXT NOT NULL,
                display_name TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                expires_at INTEGER NOT NULL,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS file_shares_expires_at
            ON file_shares(expires_at);
        """)

        user_columns = {
            row["name"]
            for row in connection.execute("PRAGMA table_info(users)")
        }
        if "storage_path" not in user_columns:
            connection.execute(
                "ALTER TABLE users ADD COLUMN storage_path TEXT NOT NULL DEFAULT ''"
            )
        if "storage_quota_bytes" not in user_columns:
            connection.execute(
                "ALTER TABLE users ADD COLUMN storage_quota_bytes INTEGER"
            )

        user_count = connection.execute(
            "SELECT COUNT(*) AS count FROM users"
        ).fetchone()["count"]

        if user_count == 0:
            username = "stoney22"
            password = secrets.token_urlsafe(18)
            now = int(time.time())

            connection.execute(
                """
                INSERT INTO users (
                    username,
                    display_name,
                    password_hash,
                    is_admin,
                    permissions,
                    is_active,
                    must_change_password,
                    created_at,
                    updated_at
                ) VALUES (?, ?, ?, 1, ?, 1, 1, ?, ?)
                """,
                (
                    username,
                    "Stoney22",
                    generate_password_hash(password),
                    json.dumps(sorted(ALL_PERMISSIONS)),
                    now,
                    now,
                ),
            )

            INITIAL_ADMIN_FILE.write_text(
                json.dumps({
                    "username": username,
                    "password": password,
                }),
                encoding="utf-8",
            )
            os.chmod(INITIAL_ADMIN_FILE, 0o600)

    os.chmod(AUTH_DB_FILE, 0o600)


def parse_permissions(raw_permissions):
    try:
        values = json.loads(raw_permissions or "[]")
    except (TypeError, json.JSONDecodeError):
        values = []

    if not isinstance(values, list):
        return set()

    return {
        str(value)
        for value in values
        if str(value) in ASSIGNABLE_PERMISSIONS
    }


def serialize_user(row):
    is_admin = bool(row["is_admin"])
    permissions = (
        ALL_PERMISSIONS
        if is_admin
        else parse_permissions(row["permissions"])
    )

    return {
        "id": row["id"],
        "username": row["username"],
        "display_name": row["display_name"],
        "is_admin": is_admin,
        "permissions": sorted(permissions),
        "storage_path": str(row["storage_path"] or ""),
        "storage_quota_bytes": row["storage_quota_bytes"],
        "is_active": bool(row["is_active"]),
        "must_change_password": bool(row["must_change_password"]),
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
    }


def validate_username(value):
    username = str(value or "").strip()

    if not 3 <= len(username) <= 32:
        raise ValueError("Der Benutzername muss 3 bis 32 Zeichen haben.")

    allowed = set(
        "abcdefghijklmnopqrstuvwxyz"
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        "0123456789._-"
    )

    if any(character not in allowed for character in username):
        raise ValueError(
            "Im Benutzernamen sind nur Buchstaben, Zahlen, Punkt, "
            "Bindestrich und Unterstrich erlaubt."
        )

    return username


def validate_display_name(value):
    display_name = str(value or "").strip()

    if not 1 <= len(display_name) <= 64:
        raise ValueError("Der Anzeigename muss 1 bis 64 Zeichen haben.")

    return display_name


def validate_password(value):
    password = str(value or "")

    if len(password) < PASSWORD_MIN_LENGTH:
        raise ValueError(
            f"Das Passwort muss mindestens {PASSWORD_MIN_LENGTH} Zeichen haben."
        )

    return password


def validate_storage_path(value):
    storage_path = str(value or "").strip().replace("\\", "/")

    if storage_path in {"", "/"}:
        return ""

    if len(storage_path) > 512 or "\x00" in storage_path:
        raise ValueError("Der Speicherordner ist ungültig oder zu lang.")

    storage_path = storage_path.strip("/")
    parts = storage_path.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        raise ValueError("Der Speicherordner enthält einen ungültigen Pfad.")

    return "/".join(parts)


def validate_storage_quota(value):
    if value is None or value == "" or value == 0 or value == "0":
        return None

    if isinstance(value, bool):
        raise ValueError("Das Speicherlimit ist ungültig.")

    try:
        quota = int(value)
    except (TypeError, ValueError) as exc:
        raise ValueError("Das Speicherlimit ist ungültig.") from exc

    if quota < 0 or quota > 100 * 1024 ** 4:
        raise ValueError("Das Speicherlimit muss zwischen 0 und 100 TB liegen.")

    return quota or None


def request_ip():
    forwarded = request.headers.get("X-Forwarded-For", "")
    if forwarded:
        return forwarded.split(",", 1)[0].strip()
    return request.remote_addr or "unknown"


def login_rate_limited(username):
    now = time.time()
    key = (request_ip(), username.casefold())

    with login_attempt_lock:
        attempts = [
            timestamp
            for timestamp in login_attempts.get(key, [])
            if timestamp > now - LOGIN_WINDOW_SECONDS
        ]
        login_attempts[key] = attempts
        return len(attempts) >= LOGIN_MAX_ATTEMPTS


def record_login_failure(username):
    key = (request_ip(), username.casefold())
    with login_attempt_lock:
        login_attempts.setdefault(key, []).append(time.time())


def clear_login_failures(username):
    key = (request_ip(), username.casefold())
    with login_attempt_lock:
        login_attempts.pop(key, None)


def bearer_token():
    authorization = request.headers.get("Authorization", "")
    if not authorization.startswith("Bearer "):
        return None
    token = authorization[7:].strip()
    return token or None


def request_session_token():
    authorization_token = bearer_token()
    if authorization_token is not None:
        return authorization_token

    cookie_token = str(request.cookies.get(SESSION_COOKIE_NAME, "")).strip()
    return cookie_token or None


def request_uses_https():
    forwarded_proto = request.headers.get("X-Forwarded-Proto", "")
    if forwarded_proto:
        return forwarded_proto.split(",", 1)[0].strip().lower() == "https"
    return request.is_secure


def set_session_cookie(response, token, remember_me):
    response.set_cookie(
        SESSION_COOKIE_NAME,
        token,
        max_age=(
            REMEMBER_SESSION_LIFETIME_SECONDS
            if remember_me
            else None
        ),
        secure=request_uses_https(),
        httponly=True,
        samesite="Lax",
        path="/api",
    )


def clear_session_cookie(response):
    response.delete_cookie(
        SESSION_COOKIE_NAME,
        secure=request_uses_https(),
        httponly=True,
        samesite="Lax",
        path="/api",
    )


def authenticated_user():
    token = request_session_token()
    if token is None:
        return None

    token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
    now = int(time.time())

    with auth_connection() as connection:
        connection.execute(
            "DELETE FROM sessions WHERE expires_at <= ?",
            (now,),
        )
        row = connection.execute(
            """
            SELECT users.*
            FROM sessions
            JOIN users ON users.id = sessions.user_id
            WHERE sessions.token_hash = ?
              AND sessions.expires_at > ?
              AND users.is_active = 1
            """,
            (token_hash, now),
        ).fetchone()

    if row is not None:
        g.auth_token = token

    return row


def authentication_required(permission=None, allow_password_change=False):
    def decorator(function):
        @wraps(function)
        def wrapped(*args, **kwargs):
            user = authenticated_user()

            if user is None:
                return jsonify({
                    "ok": False,
                    "error": "Anmeldung erforderlich.",
                    "code": "authentication_required",
                }), 401

            if user["must_change_password"] and not allow_password_change:
                return jsonify({
                    "ok": False,
                    "error": "Bitte zuerst das Passwort ändern.",
                    "code": "password_change_required",
                }), 428

            permissions = (
                ALL_PERMISSIONS
                if user["is_admin"]
                else parse_permissions(user["permissions"])
            )

            if permission is not None and permission not in permissions:
                return jsonify({
                    "ok": False,
                    "error": "Dafür hast du keine Berechtigung.",
                    "code": "permission_denied",
                }), 403

            g.auth_user = user
            g.auth_permissions = permissions
            return function(*args, **kwargs)

        return wrapped

    return decorator


def safe_read(path):
    try:
        return Path(path).read_text(encoding="utf-8", errors="ignore").strip()
    except Exception:
        return None


def run_command(args, timeout=4):
    try:
        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        return result.returncode, result.stdout.strip(), result.stderr.strip()
    except Exception as exc:
        return 1, "", str(exc)


def stop_terminal_process(process):
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return

    try:
        process.wait(timeout=0.5)
    except subprocess.TimeoutExpired:
        pass

    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def cleanup_terminal_processes():
    try:
        subprocess.run(
            ["/usr/bin/pkill", "--signal", "KILL", "--uid", TERMINAL_USER],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=2,
            check=False,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass


def clean_terminal_output(value):
    return "".join(
        character
        for character in value
        if character in {"\n", "\r", "\t"}
        or ord(character) >= 32 and ord(character) != 127
    )


def execute_terminal_command(command, cwd):
    marker = f"__PI_CONTROL_CWD_{secrets.token_hex(12)}__="
    script = """
umask 077
ulimit -t 12
ulimit -v 262144
ulimit -u 64 2>/dev/null || true
cd -- "$PI_TERMINAL_CWD" || exit 72
eval "$PI_TERMINAL_COMMAND"
status=$?
printf '\n%s%s\n' "$PI_TERMINAL_MARKER" "$PWD"
exit "$status"
""".strip()
    environment = {
        "HOME": str(TERMINAL_HOME),
        "USER": TERMINAL_USER,
        "LOGNAME": TERMINAL_USER,
        "SHELL": "/bin/bash",
        "PATH": "/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin",
        "LANG": "C.UTF-8",
        "LC_ALL": "C.UTF-8",
        "TERM": "dumb",
        "PI_TERMINAL_COMMAND": command,
        "PI_TERMINAL_CWD": cwd,
        "PI_TERMINAL_MARKER": marker,
    }
    args = [
        "/usr/sbin/runuser",
        "--user",
        TERMINAL_USER,
        "--",
        "/usr/bin/timeout",
        "--signal=TERM",
        "--kill-after=1",
        str(TERMINAL_TIMEOUT_SECONDS),
        "/bin/bash",
        "--noprofile",
        "--norc",
        "-c",
        script,
    ]

    process = subprocess.Popen(
        args,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env=environment,
        start_new_session=True,
    )
    chunks = []
    output_size = 0
    truncated = False
    timed_out = False
    deadline = time.monotonic() + TERMINAL_TIMEOUT_SECONDS + 2

    try:
        while True:
            if time.monotonic() >= deadline:
                timed_out = True
                stop_terminal_process(process)
                break

            ready, _, _ = select.select([process.stdout], [], [], 0.1)
            if ready:
                chunk = os.read(process.stdout.fileno(), 4096)
                if not chunk:
                    if process.poll() is not None:
                        break
                    continue

                remaining = TERMINAL_MAX_OUTPUT_BYTES - output_size
                if len(chunk) > remaining:
                    if remaining > 0:
                        chunks.append(chunk[:remaining])
                    truncated = True
                    stop_terminal_process(process)
                    break

                chunks.append(chunk)
                output_size += len(chunk)
            elif process.poll() is not None:
                break
    finally:
        if process.poll() is None:
            stop_terminal_process(process)
        process.wait()

    return_code = process.returncode
    if return_code in {124, 137, -signal.SIGTERM, -signal.SIGKILL}:
        timed_out = timed_out or not truncated

    output = b"".join(chunks).decode("utf-8", errors="replace")
    result_cwd = cwd
    marker_index = output.rfind(marker)

    if marker_index >= 0:
        cwd_line = output[marker_index + len(marker):].splitlines()
        if cwd_line and cwd_line[0].startswith("/"):
            result_cwd = cwd_line[0]
        output = output[:marker_index]

    return {
        "output": clean_terminal_output(output).rstrip(),
        "exit_code": return_code,
        "cwd": result_cwd,
        "timed_out": timed_out,
        "truncated": truncated,
    }


def read_cpu_snapshot():
    line = safe_read("/proc/stat")
    if not line:
        return None

    first = line.splitlines()[0].split()
    if not first or first[0] != "cpu":
        return None

    values = [int(value) for value in first[1:]]
    if len(values) < 4:
        return None

    idle = values[3]
    iowait = values[4] if len(values) > 4 else 0
    idle_all = idle + iowait
    total = sum(values)

    return idle_all, total


def get_cpu_usage():
    before = read_cpu_snapshot()
    if before is None:
        return None

    time.sleep(0.12)

    after = read_cpu_snapshot()
    if after is None:
        return None

    idle_delta = after[0] - before[0]
    total_delta = after[1] - before[1]

    if total_delta <= 0:
        return 0.0

    usage = 100.0 * (1.0 - idle_delta / total_delta)
    return round(max(0.0, min(100.0, usage)), 1)


def get_cpu_frequency_mhz():
    candidates = [
        "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq",
        "/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_cur_freq",
    ]

    for path in candidates:
        raw = safe_read(path)
        if raw:
            try:
                return round(float(raw) / 1000.0)
            except ValueError:
                pass

    code, output, _ = run_command(
        ["vcgencmd", "measure_clock", "arm"],
        timeout=2,
    )

    if code == 0 and "=" in output:
        try:
            hz = float(output.split("=", 1)[1])
            return round(hz / 1_000_000.0)
        except ValueError:
            pass

    return None


def get_temperature():
    raw = safe_read("/sys/class/thermal/thermal_zone0/temp")
    if raw:
        try:
            return round(float(raw) / 1000.0, 1)
        except ValueError:
            pass

    code, output, _ = run_command(
        ["vcgencmd", "measure_temp"],
        timeout=2,
    )

    if code == 0 and "=" in output:
        try:
            value = output.split("=", 1)[1].split("'")[0]
            return round(float(value), 1)
        except ValueError:
            pass

    return None


def get_ram():
    raw = safe_read("/proc/meminfo")
    if not raw:
        return None

    values = {}

    for line in raw.splitlines():
        if ":" not in line:
            continue

        key, rest = line.split(":", 1)
        number = rest.strip().split()[0]

        try:
            values[key] = int(number)
        except ValueError:
            continue

    total_kb = values.get("MemTotal")
    available_kb = values.get("MemAvailable")

    if total_kb is None:
        return None

    if available_kb is None:
        available_kb = (
            values.get("MemFree", 0)
            + values.get("Buffers", 0)
            + values.get("Cached", 0)
        )

    used_kb = max(0, total_kb - available_kb)
    percent = (used_kb / total_kb * 100) if total_kb else 0

    return {
        "used_mb": round(used_kb / 1024.0, 1),
        "total_mb": round(total_kb / 1024.0, 1),
        "percent": round(percent, 1),
    }


def get_disk(path):
    try:
        usage = shutil.disk_usage(path)
        total = usage.total
        used = usage.used
        free = usage.free
        percent = used / total * 100 if total else 0

        return {
            "used_gb": round(used / 1024**3, 1),
            "total_gb": round(total / 1024**3, 1),
            "free_gb": round(free / 1024**3, 1),
            "percent": round(percent, 1),
        }
    except Exception:
        return None


def service_running(service):
    code, output, _ = run_command(
        ["systemctl", "is-active", service],
        timeout=3,
    )
    return code == 0 and output.strip() == "active"


def get_tailscale():
    online = service_running("tailscaled")
    ip = None

    if online:
        code, output, _ = run_command(
            ["tailscale", "ip", "-4"],
            timeout=3,
        )

        if code == 0 and output:
            ip = output.splitlines()[0].strip()

    return {
        "online": bool(online and ip),
        "ip": ip,
    }


def get_lan_ip():
    code, output, _ = run_command(
        ["hostname", "-I"],
        timeout=2,
    )

    if code == 0 and output:
        addresses = output.split()

        for address in addresses:
            if address.startswith("192.168.") or address.startswith("10."):
                return address

        for address in addresses:
            if address.startswith("172."):
                return address

        for address in addresses:
            if not address.startswith("127.") and not address.startswith("100."):
                return address

        if addresses:
            return addresses[0]

    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.connect(("8.8.8.8", 80))
        address = sock.getsockname()[0]
        sock.close()
        return address
    except Exception:
        return "—"


def get_uptime():
    raw = safe_read("/proc/uptime")
    if not raw:
        return {
            "seconds": 0,
            "formatted": "—",
        }

    try:
        seconds = int(float(raw.split()[0]))
    except ValueError:
        seconds = 0

    days = seconds // 86400
    hours = (seconds % 86400) // 3600
    minutes = (seconds % 3600) // 60

    return {
        "seconds": seconds,
        "formatted": f"{days}d {hours}h {minutes}m",
    }


def get_model():
    raw = safe_read("/proc/device-tree/model")
    if raw:
        return raw.replace("\x00", "").strip()
    return "Raspberry Pi"


def get_os_name():
    raw = safe_read("/etc/os-release")
    if not raw:
        return platform.platform()

    values = {}
    for line in raw.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key] = value.strip().strip('"')

    return values.get("PRETTY_NAME") or values.get("NAME") or platform.platform()


def get_load_average():
    try:
        load1, load5, load15 = os.getloadavg()
        return f"{load1:.2f} / {load5:.2f} / {load15:.2f}"
    except Exception:
        return "—"


def build_alerts(info):
    alerts = []

    temperature = info.get("temperature")
    ram = info.get("ram") or {}
    sd = info.get("sd") or {}
    usb = info.get("usb")
    samba = info.get("samba")
    tailscale = info.get("tailscale") or {}

    if isinstance(temperature, (int, float)):
        if temperature >= 80:
            alerts.append({
                "key": "temperature",
                "level": "critical",
                "title": "Temperatur kritisch",
                "message": f"{temperature:.1f} °C – der Raspberry Pi ist sehr heiß.",
            })
        elif temperature >= 70:
            alerts.append({
                "key": "temperature",
                "level": "warning",
                "title": "Temperatur erhöht",
                "message": f"{temperature:.1f} °C – Kühlung prüfen.",
            })

    ram_percent = ram.get("percent")
    if isinstance(ram_percent, (int, float)) and ram_percent >= 90:
        alerts.append({
            "key": "ram",
            "level": "warning",
            "title": "RAM fast voll",
            "message": f"{ram_percent:.0f} % RAM belegt.",
        })

    sd_percent = sd.get("percent")
    if isinstance(sd_percent, (int, float)) and sd_percent >= 90:
        alerts.append({
            "key": "sd",
            "level": "critical",
            "title": "SD-Karte fast voll",
            "message": f"{sd_percent:.0f} % Speicher belegt.",
        })

    if usb is None:
        alerts.append({
            "key": "usb",
            "level": "critical",
            "title": "NAS / USB nicht gemountet",
            "message": f"{USB_PATH} ist nicht als Laufwerk eingehängt.",
        })
    else:
        usb_percent = usb.get("percent")
        usb_free = usb.get("free_gb")

        if isinstance(usb_percent, (int, float)) and usb_percent >= 90:
            alerts.append({
                "key": "usb",
                "level": "critical",
                "title": "NAS fast voll",
                "message": f"{usb_percent:.0f} % Speicher belegt.",
            })
        elif isinstance(usb_free, (int, float)) and usb_free < 10:
            alerts.append({
                "key": "usb",
                "level": "warning",
                "title": "NAS-Speicher wird knapp",
                "message": f"Nur noch {usb_free:.1f} GB frei.",
            })

    if not samba:
        alerts.append({
            "key": "samba",
            "level": "warning",
            "title": "Samba offline",
            "message": "Der NAS-Dateidienst läuft nicht.",
        })

    if not tailscale.get("online"):
        alerts.append({
            "key": "tailscale",
            "level": "warning",
            "title": "Tailscale offline",
            "message": "Der Fernzugriff ist nicht verbunden.",
        })

    return alerts


def collect_info():
    usb = None

    if os.path.ismount(USB_PATH):
        usb = get_disk(USB_PATH)

    info = {
        "hostname": socket.gethostname(),
        "ip": get_lan_ip(),
        "temperature": get_temperature(),
        "cpu": {
            "usage": get_cpu_usage(),
            "frequency_mhz": get_cpu_frequency_mhz(),
        },
        "ram": get_ram(),
        "sd": get_disk("/"),
        "usb": usb,
        "usb_path": USB_PATH,
        "samba": service_running("smbd"),
        "tailscale": get_tailscale(),
        "uptime": get_uptime(),
        "kernel": platform.release(),
        "benchmark": get_benchmark_summary(),
        "system": {
            "model": get_model(),
            "os": get_os_name(),
            "kernel": platform.release(),
            "load_average": get_load_average(),
            "notifications": (
                f"ntfy.sh/{NTFY_TOPIC}"
                if NTFY_TOPIC
                else "deaktiviert"
            ),
        },
    }

    info["alerts"] = build_alerts(info)
    return info



def load_benchmark_from_disk():
    global benchmark_data

    try:
        if not BENCHMARK_FILE.exists():
            benchmark_data = {}
            return

        raw = json.loads(
            BENCHMARK_FILE.read_text(
                encoding="utf-8",
                errors="ignore",
            )
        )

        benchmark_data = raw if isinstance(raw, dict) else {}
    except Exception as exc:
        print(f"[benchmark] Laden fehlgeschlagen: {exc}")
        benchmark_data = {}


def save_benchmark_to_disk():
    try:
        BASE_DIR.mkdir(parents=True, exist_ok=True)

        temp_file = BENCHMARK_FILE.with_suffix(".tmp")
        temp_file.write_text(
            json.dumps(
                benchmark_data,
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        temp_file.replace(BENCHMARK_FILE)
    except Exception as exc:
        print(f"[benchmark] Speichern fehlgeschlagen: {exc}")



def load_benchmark_history_from_disk():
    global benchmark_history

    try:
        if not BENCHMARK_HISTORY_FILE.exists():
            benchmark_history = []
            return

        raw = json.loads(
            BENCHMARK_HISTORY_FILE.read_text(
                encoding="utf-8",
                errors="ignore",
            )
        )

        if not isinstance(raw, list):
            benchmark_history = []
            return

        clean = [
            item
            for item in raw
            if isinstance(item, dict)
            and isinstance(item.get("score"), (int, float))
        ]

        benchmark_history = clean[
            -BENCHMARK_HISTORY_MAX_POINTS:
        ]
    except Exception as exc:
        print(
            f"[benchmark-history] Laden fehlgeschlagen: {exc}"
        )
        benchmark_history = []


def save_benchmark_history_to_disk():
    try:
        BASE_DIR.mkdir(
            parents=True,
            exist_ok=True,
        )

        temp_file = BENCHMARK_HISTORY_FILE.with_suffix(
            ".tmp"
        )

        temp_file.write_text(
            json.dumps(
                benchmark_history[
                    -BENCHMARK_HISTORY_MAX_POINTS:
                ],
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )

        temp_file.replace(
            BENCHMARK_HISTORY_FILE
        )
    except Exception as exc:
        print(
            f"[benchmark-history] Speichern fehlgeschlagen: {exc}"
        )


def add_benchmark_history(result):
    benchmark_history.append(
        {
            "score": result.get("score"),
            "best_score": result.get("best_score"),
            "duration_seconds":
                result.get("duration_seconds"),
            "temperature_before":
                result.get("temperature_before"),
            "temperature_after":
                result.get("temperature_after"),
            "temperature_delta":
                result.get("temperature_delta"),
            "frequency_before_mhz":
                result.get("frequency_before_mhz"),
            "frequency_after_mhz":
                result.get("frequency_after_mhz"),
            "timestamp": result.get("timestamp"),
        }
    )

    del benchmark_history[
        :-BENCHMARK_HISTORY_MAX_POINTS
    ]

    save_benchmark_history_to_disk()


def get_benchmark_summary():
    if not benchmark_data:
        return None

    return {
        "score": benchmark_data.get("score"),
        "best_score": benchmark_data.get("best_score"),
        "duration_seconds": benchmark_data.get("duration_seconds"),
        "temperature_before": benchmark_data.get("temperature_before"),
        "temperature_after": benchmark_data.get("temperature_after"),
        "temperature_delta": benchmark_data.get("temperature_delta"),
        "timestamp": benchmark_data.get("timestamp"),
    }


def perform_cpu_benchmark():
    temperature_before = get_temperature()
    frequency_before = get_cpu_frequency_mhz()

    duration = BENCHMARK_DURATION_SECONDS
    started = time.monotonic()
    deadline = started + duration

    payload = b"PiControl-CPU-Benchmark"
    counter = 0
    digest = payload

    while time.monotonic() < deadline:
        digest = hashlib.sha256(
            digest + counter.to_bytes(8, "little", signed=False)
        ).digest()
        counter += 1

    ended = time.monotonic()
    actual_duration = max(0.001, ended - started)

    # Eine "Punktzahl" = SHA-256-Schleifen pro Sekunde.
    # Dadurch ist der Wert reproduzierbar und "höher = besser".
    score = round(counter / actual_duration)

    temperature_after = get_temperature()
    frequency_after = get_cpu_frequency_mhz()

    if (
        isinstance(temperature_before, (int, float))
        and isinstance(temperature_after, (int, float))
    ):
        temperature_delta = round(
            temperature_after - temperature_before,
            1,
        )
    else:
        temperature_delta = None

    previous_best = benchmark_data.get("best_score")

    if not isinstance(previous_best, (int, float)):
        best_score = score
    else:
        best_score = max(int(previous_best), score)

    result = {
        "ok": True,
        "score": score,
        "best_score": best_score,
        "iterations": counter,
        "duration_seconds": round(actual_duration, 2),
        "temperature_before": temperature_before,
        "temperature_after": temperature_after,
        "temperature_delta": temperature_delta,
        "frequency_before_mhz": frequency_before,
        "frequency_after_mhz": frequency_after,
        "timestamp": int(time.time()),
    }

    benchmark_data.clear()
    benchmark_data.update(result)
    save_benchmark_to_disk()

    add_benchmark_history(result)

    # Referenzvariable bewusst verwenden, damit die Berechnung
    # nicht als unbenutzt wegoptimiert werden könnte.
    if not digest:
        raise RuntimeError("Benchmark-Hash fehlgeschlagen")

    return result


def load_history_from_disk():
    global history_points

    try:
        if not HISTORY_FILE.exists():
            history_points = []
            return

        raw = json.loads(
            HISTORY_FILE.read_text(
                encoding="utf-8",
                errors="ignore",
            )
        )

        if isinstance(raw, list):
            cutoff = int(time.time()) - 24 * 60 * 60
            clean = []

            for point in raw:
                if not isinstance(point, dict):
                    continue

                ts = point.get("ts")
                if isinstance(ts, (int, float)) and ts >= cutoff:
                    clean.append(point)

            history_points = clean[-HISTORY_MAX_POINTS:]
    except Exception as exc:
        print(f"[history] Laden fehlgeschlagen: {exc}")
        history_points = []


def save_history_to_disk():
    try:
        BASE_DIR.mkdir(parents=True, exist_ok=True)

        with history_lock:
            payload = list(history_points)

        temp_file = HISTORY_FILE.with_suffix(".tmp")
        temp_file.write_text(
            json.dumps(payload, ensure_ascii=False),
            encoding="utf-8",
        )
        temp_file.replace(HISTORY_FILE)
    except Exception as exc:
        print(f"[history] Speichern fehlgeschlagen: {exc}")


def add_history_point(info):
    point = {
        "ts": int(time.time()),
        "cpu": (info.get("cpu") or {}).get("usage"),
        "ram": (info.get("ram") or {}).get("percent"),
        "temperature": info.get("temperature"),
    }

    cutoff = int(time.time()) - 24 * 60 * 60

    with history_lock:
        history_points.append(point)

        history_points[:] = [
            item
            for item in history_points
            if isinstance(item.get("ts"), (int, float))
            and item["ts"] >= cutoff
        ][-HISTORY_MAX_POINTS:]


def send_ntfy(title, message, priority="default", tags="warning"):
    if not NTFY_TOPIC:
        return

    try:
        req = urllib.request.Request(
            f"https://ntfy.sh/{NTFY_TOPIC}",
            data=message.encode("utf-8"),
            method="POST",
            headers={
                "Title": title,
                "Priority": priority,
                "Tags": tags,
            },
        )

        with urllib.request.urlopen(req, timeout=8) as response:
            response.read(32)
    except Exception as exc:
        print(f"[ntfy] Senden fehlgeschlagen: {exc}")


def process_alert_notifications(alerts):
    current = {
        item["key"]: item
        for item in alerts
        if item.get("key")
    }

    with alert_lock:
        known_keys = set(last_alert_states.keys()) | set(current.keys())

        for key in known_keys:
            previous = last_alert_states.get(key)
            now = current.get(key)

            if now is not None:
                signature = f"{now.get('level')}|{now.get('title')}"

                if previous != signature:
                    priority = (
                        "urgent"
                        if now.get("level") == "critical"
                        else "high"
                    )

                    send_ntfy(
                        f"Pi Control: {now.get('title', 'Warnung')}",
                        now.get("message", "Warnung erkannt."),
                        priority=priority,
                        tags="warning",
                    )

                    last_alert_states[key] = signature

            elif previous is not None:
                send_ntfy(
                    "Pi Control: Problem behoben",
                    f"{key}: Status ist wieder normal.",
                    priority="default",
                    tags="white_check_mark",
                )

                last_alert_states.pop(key, None)


def monitor_loop():
    while True:
        started = time.monotonic()

        try:
            info = collect_info()
            add_history_point(info)
            save_history_to_disk()
            process_alert_notifications(info.get("alerts", []))
        except Exception as exc:
            print(f"[monitor] Fehler: {exc}")

        elapsed = time.monotonic() - started
        wait = max(5, HISTORY_INTERVAL_SECONDS - elapsed)
        time.sleep(wait)


@app.get("/api/auth/status")
def api_auth_status():
    return jsonify({
        "ok": True,
        "ready": AUTH_DB_FILE.exists(),
        "password_min_length": PASSWORD_MIN_LENGTH,
    })


@app.post("/api/auth/login")
def api_auth_login():
    payload = request.get_json(silent=True) or {}
    username = str(payload.get("username", "")).strip()
    password = str(payload.get("password", ""))
    remember_me = payload.get("remember_me") is True
    cookie_only = payload.get("cookie_only") is True

    if login_rate_limited(username):
        return jsonify({
            "ok": False,
            "error": "Zu viele Anmeldeversuche. Bitte später erneut versuchen.",
            "code": "rate_limited",
        }), 429

    with auth_connection() as connection:
        user = connection.execute(
            "SELECT * FROM users WHERE username = ? COLLATE NOCASE",
            (username,),
        ).fetchone()

        if (
            user is None
            or not user["is_active"]
            or not check_password_hash(user["password_hash"], password)
        ):
            record_login_failure(username)
            return jsonify({
                "ok": False,
                "error": "Benutzername oder Passwort ist falsch.",
                "code": "invalid_credentials",
            }), 401

        clear_login_failures(username)
        token = secrets.token_urlsafe(40)
        token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
        now = int(time.time())
        expires_at = now + (
            REMEMBER_SESSION_LIFETIME_SECONDS
            if remember_me
            else SESSION_LIFETIME_SECONDS
        )

        connection.execute(
            """
            INSERT INTO sessions (
                token_hash,
                user_id,
                created_at,
                expires_at
            ) VALUES (?, ?, ?, ?)
            """,
            (token_hash, user["id"], now, expires_at),
        )

    response = jsonify({
        "ok": True,
        "token": None if cookie_only else token,
        "expires_at": expires_at,
        "user": serialize_user(user),
    })
    set_session_cookie(response, token, remember_me)
    return response


@app.get("/api/auth/me")
@authentication_required(allow_password_change=True)
def api_auth_me():
    return jsonify({
        "ok": True,
        "user": serialize_user(g.auth_user),
    })


@app.post("/api/auth/logout")
def api_auth_logout():
    token = request_session_token()

    if token is not None:
        token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()

        with auth_connection() as connection:
            connection.execute(
                "DELETE FROM sessions WHERE token_hash = ?",
                (token_hash,),
            )

    response = jsonify({"ok": True})
    clear_session_cookie(response)
    return response


@app.post("/api/auth/password")
@authentication_required(allow_password_change=True)
def api_auth_password():
    payload = request.get_json(silent=True) or {}
    current_password = str(payload.get("current_password", ""))

    if not check_password_hash(
        g.auth_user["password_hash"],
        current_password,
    ):
        return jsonify({
            "ok": False,
            "error": "Das aktuelle Passwort ist falsch.",
        }), 403

    try:
        new_password = validate_password(payload.get("new_password"))
    except ValueError as exc:
        return jsonify({"ok": False, "error": str(exc)}), 400

    token = g.auth_token
    token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
    now = int(time.time())

    with auth_connection() as connection:
        connection.execute(
            """
            UPDATE users
            SET password_hash = ?,
                must_change_password = 0,
                updated_at = ?
            WHERE id = ?
            """,
            (
                generate_password_hash(new_password),
                now,
                g.auth_user["id"],
            ),
        )
        connection.execute(
            """
            DELETE FROM sessions
            WHERE user_id = ? AND token_hash != ?
            """,
            (g.auth_user["id"], token_hash),
        )
        updated_user = connection.execute(
            "SELECT * FROM users WHERE id = ?",
            (g.auth_user["id"],),
        ).fetchone()

    if INITIAL_ADMIN_FILE.exists():
        try:
            INITIAL_ADMIN_FILE.unlink()
        except OSError:
            pass

    return jsonify({
        "ok": True,
        "user": serialize_user(updated_user),
    })


def requested_permissions(payload):
    values = payload.get("permissions", [])
    if not isinstance(values, list):
        raise ValueError("Ungültige Berechtigungsliste.")
    permissions = {str(value) for value in values} & ASSIGNABLE_PERMISSIONS
    permissions.add("dashboard_view")
    return sorted(permissions)


@app.get("/api/admin/users")
@authentication_required("users_manage")
def api_admin_users():
    with auth_connection() as connection:
        users = connection.execute(
            "SELECT * FROM users ORDER BY username COLLATE NOCASE"
        ).fetchall()

    return jsonify({
        "ok": True,
        "users": [serialize_user(user) for user in users],
        "permission_definitions": PERMISSION_DEFINITIONS,
    })


@app.post("/api/admin/users")
@authentication_required("users_manage")
def api_admin_create_user():
    payload = request.get_json(silent=True) or {}

    try:
        username = validate_username(payload.get("username"))
        display_name = validate_display_name(
            payload.get("display_name") or username
        )
        password = validate_password(payload.get("password"))
        is_admin = bool(payload.get("is_admin", False))
        permissions = (
            sorted(ALL_PERMISSIONS)
            if is_admin
            else requested_permissions(payload)
        )
        storage_path = (
            ""
            if is_admin
            else validate_storage_path(
                payload.get("storage_path", f"users/{username}")
            )
        )
        storage_quota_bytes = (
            None
            if is_admin
            else validate_storage_quota(payload.get("storage_quota_bytes"))
        )
        now = int(time.time())

        with auth_connection() as connection:
            cursor = connection.execute(
                """
                INSERT INTO users (
                    username,
                    display_name,
                    password_hash,
                    is_admin,
                    permissions,
                    storage_path,
                    storage_quota_bytes,
                    is_active,
                    must_change_password,
                    created_at,
                    updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, 1, 1, ?, ?)
                """,
                (
                    username,
                    display_name,
                    generate_password_hash(password),
                    1 if is_admin else 0,
                    json.dumps(permissions),
                    storage_path,
                    storage_quota_bytes,
                    now,
                    now,
                ),
            )
            user = connection.execute(
                "SELECT * FROM users WHERE id = ?",
                (cursor.lastrowid,),
            ).fetchone()

        return jsonify({
            "ok": True,
            "user": serialize_user(user),
        }), 201
    except sqlite3.IntegrityError:
        return jsonify({
            "ok": False,
            "error": "Dieser Benutzername ist bereits vergeben.",
        }), 409
    except ValueError as exc:
        return jsonify({"ok": False, "error": str(exc)}), 400


@app.patch("/api/admin/users/<int:user_id>")
@authentication_required("users_manage")
def api_admin_update_user(user_id):
    payload = request.get_json(silent=True) or {}

    with auth_connection() as connection:
        target = connection.execute(
            "SELECT * FROM users WHERE id = ?",
            (user_id,),
        ).fetchone()

        if target is None:
            return jsonify({
                "ok": False,
                "error": "Benutzer nicht gefunden.",
            }), 404

        try:
            username = validate_username(
                payload.get("username", target["username"])
            )
            display_name = validate_display_name(
                payload.get("display_name", target["display_name"])
            )
            is_admin = bool(payload.get("is_admin", target["is_admin"]))
            is_active = bool(payload.get("is_active", target["is_active"]))
            permissions = (
                sorted(ALL_PERMISSIONS)
                if is_admin
                else requested_permissions(payload)
            )
            storage_path = (
                ""
                if is_admin
                else validate_storage_path(
                    payload.get("storage_path", target["storage_path"])
                )
            )
            storage_quota_bytes = (
                None
                if is_admin
                else validate_storage_quota(
                    payload.get(
                        "storage_quota_bytes",
                        target["storage_quota_bytes"],
                    )
                )
            )

            if user_id == g.auth_user["id"] and (
                not is_admin or not is_active
            ):
                return jsonify({
                    "ok": False,
                    "error": "Du kannst dein eigenes Administratorkonto nicht sperren oder herabstufen.",
                }), 409

            password = payload.get("password")
            password_hash = target["password_hash"]
            must_change_password = target["must_change_password"]

            if password not in {None, ""}:
                password_hash = generate_password_hash(
                    validate_password(password)
                )
                must_change_password = 1

            now = int(time.time())
            connection.execute(
                """
                UPDATE users
                SET username = ?,
                    display_name = ?,
                    password_hash = ?,
                    is_admin = ?,
                    permissions = ?,
                    storage_path = ?,
                    storage_quota_bytes = ?,
                    is_active = ?,
                    must_change_password = ?,
                    updated_at = ?
                WHERE id = ?
                """,
                (
                    username,
                    display_name,
                    password_hash,
                    1 if is_admin else 0,
                    json.dumps(permissions),
                    storage_path,
                    storage_quota_bytes,
                    1 if is_active else 0,
                    must_change_password,
                    now,
                    user_id,
                ),
            )

            if not is_active or password not in {None, ""}:
                connection.execute(
                    "DELETE FROM sessions WHERE user_id = ?",
                    (user_id,),
                )

            user = connection.execute(
                "SELECT * FROM users WHERE id = ?",
                (user_id,),
            ).fetchone()
        except sqlite3.IntegrityError:
            return jsonify({
                "ok": False,
                "error": "Dieser Benutzername ist bereits vergeben.",
            }), 409
        except ValueError as exc:
            return jsonify({"ok": False, "error": str(exc)}), 400

    return jsonify({
        "ok": True,
        "user": serialize_user(user),
    })


def file_api_error(message, status=400):
    return jsonify({
        "ok": False,
        "error": message,
    }), status


def require_file_root():
    if not FILE_ROOT.exists() or not os.path.ismount(FILE_ROOT):
        raise RuntimeError("Der NAS-/USB-Speicher ist nicht eingehängt.")

    return FILE_ROOT.resolve(strict=True)


def assigned_file_root(user=None):
    base_root = require_file_root()
    account = user if user is not None else g.auth_user
    storage_path = (
        ""
        if bool(account["is_admin"])
        else validate_storage_path(account["storage_path"])
    )
    quota = (
        None
        if bool(account["is_admin"])
        else validate_storage_quota(account["storage_quota_bytes"])
    )
    root = (base_root / storage_path).resolve(strict=False)

    try:
        root.relative_to(base_root)
    except ValueError as exc:
        raise ValueError("Der zugewiesene Speicherordner ist ungültig.") from exc

    root_existed = root.exists()
    root.mkdir(parents=True, exist_ok=True)
    if not root_existed:
        set_file_owner(root, directory=True)
    root = root.resolve(strict=True)

    try:
        root.relative_to(base_root)
    except ValueError as exc:
        raise ValueError("Der zugewiesene Speicherordner liegt außerhalb des NAS.") from exc

    if not root.is_dir():
        raise RuntimeError("Der zugewiesene Speicherpfad ist kein Ordner.")

    return root, storage_path, quota


def set_file_owner(path, directory=False):
    try:
        shutil.chown(path, user=FILE_OWNER_USER, group=FILE_OWNER_USER)
        os.chmod(path, 0o775 if directory else 0o664)
    except (LookupError, OSError):
        pass


def resolve_file_path(relative_path=""):
    root, _, _ = assigned_file_root()
    normalized = str(relative_path or "").replace("\\", "/").lstrip("/")
    if normalized.split("/", 1)[0] == TRASH_DIRECTORY_NAME:
        raise ValueError("Dieser interne Ordner ist geschützt.")
    candidate = (root / normalized).resolve(strict=False)

    try:
        candidate.relative_to(root)
    except ValueError as exc:
        raise ValueError("Ungültiger Dateipfad.") from exc

    return root, candidate


def storage_used_bytes(root):
    total = 0
    pending = [root]

    while pending:
        current = pending.pop()
        try:
            with os.scandir(current) as entries:
                for entry in entries:
                    try:
                        if entry.is_symlink():
                            continue
                        if entry.is_dir(follow_symlinks=False):
                            pending.append(Path(entry.path))
                        elif entry.is_file(follow_symlinks=False):
                            total += entry.stat(follow_symlinks=False).st_size
                    except OSError:
                        continue
        except OSError:
            continue

    return total


def validate_file_name(name):
    value = str(name or "").strip()

    if (
        not value
        or value in {".", ".."}
        or value == TRASH_DIRECTORY_NAME
        or "/" in value
        or "\\" in value
        or "\x00" in value
    ):
        raise ValueError("Ungültiger Dateiname.")

    return value


def relative_file_path(root, path):
    relative = path.relative_to(root).as_posix()
    return "" if relative == "." else relative


def describe_file(root, path):
    stat = path.stat()
    is_directory = path.is_dir()

    return {
        "name": path.name,
        "path": relative_file_path(root, path),
        "is_directory": is_directory,
        "size": None if is_directory else stat.st_size,
        "modified": int(stat.st_mtime),
    }


def hidden_file_entry(path):
    return path.name == TRASH_DIRECTORY_NAME


def current_user_id():
    return int(g.auth_user["id"])


def trash_directory(root):
    directory = root / TRASH_DIRECTORY_NAME
    directory.mkdir(mode=0o700, exist_ok=True)
    try:
        os.chmod(directory, 0o700)
    except OSError:
        pass
    return directory


def resolve_stored_file(root_path, relative_path):
    root = Path(root_path).resolve(strict=True)
    candidate = (root / str(relative_path or "")).resolve(strict=False)
    try:
        candidate.relative_to(root)
    except ValueError as exc:
        raise ValueError("Ungültiger gespeicherter Dateipfad.") from exc
    return root, candidate


@app.get("/api/files")
@authentication_required("files_view")
def api_files():
    try:
        root, current = resolve_file_path(request.args.get("path", ""))
        _, storage_path, quota = assigned_file_root()

        if not current.exists() or not current.is_dir():
            return file_api_error("Ordner nicht gefunden.", 404)

        entries = []

        for child in current.iterdir():
            try:
                if child.is_symlink() or hidden_file_entry(child):
                    continue

                entries.append(describe_file(root, child))
            except (OSError, ValueError):
                continue

        entries.sort(
            key=lambda item: (
                not item["is_directory"],
                item["name"].casefold(),
            )
        )

        current_path = relative_file_path(root, current)
        parent_path = None

        if current != root:
            parent_path = relative_file_path(root, current.parent)

        return jsonify({
            "ok": True,
            "root_name": storage_path or "NAS / USB-Stick",
            "storage_path": storage_path,
            "storage_used_bytes": (
                storage_used_bytes(root) if quota is not None else None
            ),
            "storage_quota_bytes": quota,
            "path": current_path,
            "parent": parent_path,
            "entries": entries,
        })
    except (OSError, RuntimeError, ValueError) as exc:
        return file_api_error(str(exc), 409)


@app.get("/api/files/search")
@authentication_required("files_view")
def api_files_search():
    query = str(request.args.get("q") or "").strip().casefold()
    if len(query) < 2:
        return file_api_error("Bitte mindestens zwei Zeichen eingeben.")

    try:
        root, _, _ = assigned_file_root()
        results = []
        visited = 0

        for current, directories, files in os.walk(root, followlinks=False):
            directories[:] = [
                name for name in directories
                if name != TRASH_DIRECTORY_NAME
                and not (Path(current) / name).is_symlink()
            ]

            for name in [*directories, *files]:
                visited += 1
                if visited > SEARCH_VISIT_LIMIT:
                    break
                if query not in name.casefold():
                    continue

                path = Path(current) / name
                try:
                    if path.is_symlink():
                        continue
                    results.append(describe_file(root, path))
                except (OSError, ValueError):
                    continue

                if len(results) >= SEARCH_RESULT_LIMIT:
                    break

            if visited > SEARCH_VISIT_LIMIT or len(results) >= SEARCH_RESULT_LIMIT:
                break

        results.sort(key=lambda item: (
            not item["is_directory"], item["path"].casefold()
        ))
        return jsonify({
            "ok": True,
            "query": query,
            "results": results,
            "limited": (
                visited > SEARCH_VISIT_LIMIT
                or len(results) >= SEARCH_RESULT_LIMIT
            ),
        })
    except (OSError, RuntimeError, ValueError) as exc:
        return file_api_error(str(exc), 409)


@app.post("/api/files/folder")
@authentication_required("files_manage")
def api_files_create_folder():
    payload = request.get_json(silent=True) or {}

    try:
        _, parent = resolve_file_path(payload.get("path", ""))
        name = validate_file_name(payload.get("name"))

        if not parent.exists() or not parent.is_dir():
            return file_api_error("Zielordner nicht gefunden.", 404)

        target = parent / name

        if target.exists():
            return file_api_error("Dieser Name ist bereits vergeben.", 409)

        target.mkdir()
        set_file_owner(target, directory=True)
        return jsonify({"ok": True})
    except (OSError, RuntimeError, ValueError) as exc:
        return file_api_error(str(exc), 409)


@app.post("/api/files/rename")
@authentication_required("files_manage")
def api_files_rename():
    payload = request.get_json(silent=True) or {}

    try:
        root, source = resolve_file_path(payload.get("path", ""))
        new_name = validate_file_name(payload.get("name"))

        if source == root:
            return file_api_error("Der Hauptordner kann nicht umbenannt werden.")

        if not source.exists():
            return file_api_error("Datei nicht gefunden.", 404)

        target = source.parent / new_name

        if target.exists():
            return file_api_error("Dieser Name ist bereits vergeben.", 409)

        source.rename(target)
        return jsonify({"ok": True})
    except (OSError, RuntimeError, ValueError) as exc:
        return file_api_error(str(exc), 409)


@app.post("/api/files/move")
@authentication_required("files_manage")
def api_files_move():
    payload = request.get_json(silent=True) or {}

    try:
        root, source = resolve_file_path(payload.get("path", ""))
        _, destination = resolve_file_path(payload.get("destination", ""))

        if source == root:
            return file_api_error("Der Hauptordner kann nicht verschoben werden.")

        if not source.exists():
            return file_api_error("Datei nicht gefunden.", 404)

        if not destination.exists() or not destination.is_dir():
            return file_api_error("Zielordner nicht gefunden.", 404)

        if destination == source.parent:
            return file_api_error("Die Datei befindet sich bereits in diesem Ordner.")

        if source.is_dir():
            try:
                destination.relative_to(source)
                return file_api_error(
                    "Ein Ordner kann nicht in sich selbst verschoben werden.",
                    409,
                )
            except ValueError:
                pass

        target = destination / source.name

        if target.exists():
            return file_api_error("Im Zielordner ist dieser Name bereits vergeben.", 409)

        with file_operation_lock:
            source.rename(target)

        return jsonify({
            "ok": True,
            "path": relative_file_path(root, target),
        })
    except (OSError, RuntimeError, ValueError) as exc:
        return file_api_error(str(exc), 409)


@app.post("/api/files/delete")
@authentication_required("files_manage")
def api_files_delete():
    payload = request.get_json(silent=True) or {}

    try:
        root, target = resolve_file_path(payload.get("path", ""))

        if target == root:
            return file_api_error("Der Hauptordner kann nicht gelöscht werden.")

        if not target.exists():
            return file_api_error("Datei nicht gefunden.", 404)

        trash = trash_directory(root)
        trash_name = f"{int(time.time())}-{secrets.token_hex(8)}-{target.name}"
        trashed_target = trash / trash_name
        original_path = relative_file_path(root, target)
        is_directory = target.is_dir()

        with file_operation_lock:
            target.rename(trashed_target)
            try:
                with auth_connection() as connection:
                    connection.execute(
                        """
                        INSERT INTO trash_items (
                            user_id, root_path, trash_name, original_path,
                            display_name, is_directory, deleted_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            current_user_id(), str(root), trash_name,
                            original_path, target.name, int(is_directory),
                            int(time.time()),
                        ),
                    )
            except Exception:
                trashed_target.rename(target)
                raise

        return jsonify({"ok": True, "trashed": True})
    except OSError as exc:
        return file_api_error(str(exc), 409)
    except (RuntimeError, ValueError) as exc:
        return file_api_error(str(exc), 409)


@app.get("/api/files/trash")
@authentication_required("files_manage")
def api_files_trash():
    try:
        root, _, _ = assigned_file_root()
        with auth_connection() as connection:
            rows = connection.execute(
                """
                SELECT id, root_path, original_path, display_name,
                       is_directory, deleted_at
                FROM trash_items
                WHERE user_id = ?
                ORDER BY deleted_at DESC, id DESC
                """,
                (current_user_id(),),
            ).fetchall()

        items = [
            {
                "id": row["id"],
                "name": row["display_name"],
                "original_path": row["original_path"],
                "is_directory": bool(row["is_directory"]),
                "deleted_at": row["deleted_at"],
            }
            for row in rows
            if Path(row["root_path"]).resolve(strict=False) == root
        ]
        return jsonify({"ok": True, "items": items})
    except (OSError, RuntimeError, ValueError) as exc:
        return file_api_error(str(exc), 409)


def get_trash_item(item_id):
    with auth_connection() as connection:
        return connection.execute(
            "SELECT * FROM trash_items WHERE id = ? AND user_id = ?",
            (item_id, current_user_id()),
        ).fetchone()


@app.post("/api/files/trash/restore")
@authentication_required("files_manage")
def api_files_trash_restore():
    payload = request.get_json(silent=True) or {}
    try:
        item_id = int(payload.get("id"))
        row = get_trash_item(item_id)
        if row is None:
            return file_api_error("Papierkorb-Eintrag nicht gefunden.", 404)

        current_root, _, _ = assigned_file_root()
        stored_root = Path(row["root_path"]).resolve(strict=True)
        if stored_root != current_root:
            return file_api_error("Der ursprüngliche Speicherordner ist nicht mehr zugewiesen.", 409)

        source = trash_directory(current_root) / row["trash_name"]
        _, target = resolve_stored_file(stored_root, row["original_path"])
        if not source.exists():
            return file_api_error("Die Datei ist nicht mehr im Papierkorb.", 404)
        if target.exists():
            return file_api_error("Am ursprünglichen Ort ist der Name bereits vergeben.", 409)

        target.parent.mkdir(parents=True, exist_ok=True)
        with file_operation_lock:
            source.rename(target)
            with auth_connection() as connection:
                connection.execute("DELETE FROM trash_items WHERE id = ?", (item_id,))

        return jsonify({"ok": True, "path": relative_file_path(current_root, target)})
    except (OSError, RuntimeError, TypeError, ValueError) as exc:
        return file_api_error(str(exc), 409)


@app.post("/api/files/trash/permanent-delete")
@authentication_required("files_manage")
def api_files_trash_permanent_delete():
    payload = request.get_json(silent=True) or {}
    try:
        item_id = int(payload.get("id"))
        row = get_trash_item(item_id)
        if row is None:
            return file_api_error("Papierkorb-Eintrag nicht gefunden.", 404)

        current_root, _, _ = assigned_file_root()
        stored_root = Path(row["root_path"]).resolve(strict=True)
        if stored_root != current_root:
            return file_api_error("Der Speicherordner ist nicht mehr zugewiesen.", 409)

        trash = trash_directory(current_root).resolve(strict=True)
        target = (trash / row["trash_name"]).resolve(strict=False)
        try:
            target.relative_to(trash)
        except ValueError as exc:
            raise ValueError("Ungültiger Papierkorb-Pfad.") from exc

        with file_operation_lock:
            if target.is_dir():
                shutil.rmtree(target)
            elif target.exists():
                target.unlink()
            with auth_connection() as connection:
                connection.execute("DELETE FROM trash_items WHERE id = ?", (item_id,))

        return jsonify({"ok": True})
    except (OSError, RuntimeError, TypeError, ValueError) as exc:
        return file_api_error(str(exc), 409)


@app.post("/api/files/upload")
@authentication_required("files_upload")
def api_files_upload():
    uploaded_file = request.files.get("file")

    if uploaded_file is None:
        return file_api_error("Keine Datei ausgewählt.")

    temporary_target = None

    try:
        root, parent = resolve_file_path(request.form.get("path", ""))
        _, _, quota = assigned_file_root()
        name = validate_file_name(uploaded_file.filename)

        if not parent.exists() or not parent.is_dir():
            return file_api_error("Zielordner nicht gefunden.", 404)

        target = parent / name

        with file_operation_lock:
            if target.exists():
                return file_api_error("Die Datei existiert bereits.", 409)

            used = storage_used_bytes(root)
            temporary_target = parent / (
                f".{name}.upload-{secrets.token_hex(8)}.part"
            )
            uploaded_file.save(temporary_target)
            upload_size = temporary_target.stat().st_size

            if quota is not None and used + upload_size > quota:
                free = max(0, quota - used)
                return file_api_error(
                    "Speicherlimit überschritten. "
                    f"Noch {free / 1024 ** 3:.2f} GB verfügbar.",
                    413,
                )

            temporary_target.replace(target)
            set_file_owner(target)
            temporary_target = None

        return jsonify({
            "ok": True,
            "name": name,
            "storage_used_bytes": used + upload_size,
            "storage_quota_bytes": quota,
        })
    except (OSError, RuntimeError, ValueError) as exc:
        return file_api_error(str(exc), 409)
    finally:
        if temporary_target is not None:
            try:
                temporary_target.unlink(missing_ok=True)
            except OSError:
                pass


@app.post("/api/files/download-token")
@authentication_required("files_view")
def api_files_download_token():
    payload = request.get_json(silent=True) or {}

    try:
        root, target = resolve_file_path(payload.get("path", ""))

        if not target.exists() or not target.is_file():
            return file_api_error("Datei nicht gefunden.", 404)

        token = secrets.token_urlsafe(24)
        now = time.time()

        with download_token_lock:
            expired = [
                key
                for key, item in download_tokens.items()
                if item["expires"] <= now
            ]

            for key in expired:
                download_tokens.pop(key, None)

            download_tokens[token] = {
                "path": str(target),
                "root": str(root),
                "inline": bool(payload.get("preview")),
                "expires": now + DOWNLOAD_TOKEN_LIFETIME_SECONDS,
            }

        return jsonify({
            "ok": True,
            "token": token,
        })
    except (OSError, RuntimeError, ValueError) as exc:
        return file_api_error(str(exc), 409)


@app.get("/api/files/download/<token>")
def api_files_download(token):
    with download_token_lock:
        item = download_tokens.pop(token, None)

    if item is None or item["expires"] <= time.time():
        return file_api_error("Download-Link ist abgelaufen.", 404)

    try:
        root = Path(item["root"]).resolve(strict=True)
        target = Path(item["path"]).resolve(strict=True)

        target.relative_to(root)

        if not target.exists() or not target.is_file():
            return file_api_error("Datei nicht gefunden.", 404)

        return send_file(
            target,
            as_attachment=not bool(item.get("inline")),
            download_name=target.name,
        )
    except (OSError, RuntimeError, ValueError) as exc:
        return file_api_error(str(exc), 409)


@app.post("/api/files/share")
@authentication_required("files_view")
def api_files_share_create():
    payload = request.get_json(silent=True) or {}
    try:
        root, target = resolve_file_path(payload.get("path", ""))
        if not target.exists() or not target.is_file():
            return file_api_error("Nur vorhandene Dateien können geteilt werden.", 404)

        requested_hours = int(payload.get("hours", 24))
        hours = max(1, min(requested_hours, 7 * 24))
        token = secrets.token_urlsafe(32)
        now = int(time.time())
        expires_at = now + hours * 60 * 60

        with auth_connection() as connection:
            connection.execute(
                "DELETE FROM file_shares WHERE expires_at <= ?",
                (now,),
            )
            connection.execute(
                """
                INSERT INTO file_shares (
                    token_hash, user_id, root_path, relative_path,
                    display_name, created_at, expires_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    hashlib.sha256(token.encode("utf-8")).hexdigest(),
                    current_user_id(), str(root),
                    relative_file_path(root, target), target.name,
                    now, expires_at,
                ),
            )

        return jsonify({
            "ok": True,
            "token": token,
            "expires_at": expires_at,
        })
    except (OSError, RuntimeError, TypeError, ValueError) as exc:
        return file_api_error(str(exc), 409)


@app.get("/api/files/shares")
@authentication_required("files_view")
def api_files_shares_list():
    now = int(time.time())
    try:
        with auth_connection() as connection:
            connection.execute("DELETE FROM file_shares WHERE expires_at <= ?", (now,))
            rows = connection.execute(
                """
                SELECT token_hash, relative_path, display_name,
                       created_at, expires_at
                FROM file_shares
                WHERE user_id = ? AND expires_at > ?
                ORDER BY created_at DESC
                """,
                (current_user_id(), now),
            ).fetchall()

        return jsonify({
            "ok": True,
            "shares": [
                {
                    "id": row["token_hash"],
                    "path": row["relative_path"],
                    "name": row["display_name"],
                    "created_at": row["created_at"],
                    "expires_at": row["expires_at"],
                }
                for row in rows
            ],
        })
    except (OSError, RuntimeError, ValueError) as exc:
        return file_api_error(str(exc), 409)


@app.post("/api/files/shares/revoke")
@authentication_required("files_view")
def api_files_shares_revoke():
    payload = request.get_json(silent=True) or {}
    share_id = str(payload.get("id") or "").strip()
    if len(share_id) != 64:
        return file_api_error("Ungültiger Freigabelink.")

    with auth_connection() as connection:
        cursor = connection.execute(
            "DELETE FROM file_shares WHERE token_hash = ? AND user_id = ?",
            (share_id, current_user_id()),
        )
    if cursor.rowcount == 0:
        return file_api_error("Freigabelink nicht gefunden.", 404)
    return jsonify({"ok": True})


@app.get("/api/files/share/<token>")
def api_files_share_download(token):
    now = int(time.time())
    try:
        with auth_connection() as connection:
            row = connection.execute(
                """
                SELECT root_path, relative_path, display_name, expires_at
                FROM file_shares
                WHERE token_hash = ? AND expires_at > ?
                """,
                (hashlib.sha256(token.encode("utf-8")).hexdigest(), now),
            ).fetchone()

        if row is None:
            return file_api_error("Freigabelink ist ungültig oder abgelaufen.", 404)

        _, target = resolve_stored_file(row["root_path"], row["relative_path"])
        if not target.exists() or not target.is_file():
            return file_api_error("Die freigegebene Datei wurde nicht gefunden.", 404)

        return send_file(
            target,
            as_attachment=False,
            download_name=row["display_name"],
        )
    except (OSError, RuntimeError, ValueError) as exc:
        return file_api_error(str(exc), 409)


@app.get("/api/info")
@authentication_required("dashboard_view")
def api_info():
    try:
        return jsonify(collect_info())
    except Exception as exc:
        return jsonify({
            "error": str(exc),
        }), 500


@app.get("/api/app-version")
def api_app_version():
    return jsonify({
        "ok": True,
        "latest_version": APP_VERSION,
        "android_download": f"/api/app-update/android/{APP_VERSION}",
        "ios_distribution": "TestFlight/App Store wird vorbereitet",
    })


@app.get("/api/app-update/android/<version>")
def api_app_update_android(version):
    if version != APP_VERSION:
        return file_api_error("Diese App-Version ist nicht verfügbar.", 404)
    apk = FILE_ROOT / "App" / ".apk" / f"Pi-Control-{APP_VERSION}.apk"
    if not apk.exists() or not apk.is_file():
        return file_api_error("Die Android-Aktualisierung ist noch nicht veröffentlicht.", 404)
    return send_file(apk, as_attachment=True, download_name=apk.name)


def require_admin_account():
    if not bool(g.auth_user["is_admin"]):
        return jsonify({
            "ok": False,
            "error": "Diese Funktion ist nur für Administratoren verfügbar.",
            "code": "administrator_required",
        }), 403
    return None


@app.get("/api/backups")
@authentication_required("users_manage")
def api_backups_list():
    denied = require_admin_account()
    if denied is not None:
        return denied
    try:
        BACKUP_DIRECTORY.mkdir(parents=True, exist_ok=True)
        backups = []
        for path in BACKUP_DIRECTORY.glob("pi-control-*.tar.gz"):
            try:
                stat = path.stat()
                backups.append({
                    "name": path.name,
                    "size": stat.st_size,
                    "created_at": int(stat.st_mtime),
                })
            except OSError:
                continue
        backups.sort(key=lambda item: item["created_at"], reverse=True)
        return jsonify({"ok": True, "backups": backups})
    except OSError as exc:
        return file_api_error(str(exc), 409)


@app.post("/api/backups/create")
@authentication_required("users_manage")
def api_backups_create():
    denied = require_admin_account()
    if denied is not None:
        return denied
    try:
        result = subprocess.run(
            [str(BACKUP_SCRIPT)],
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )
        if result.returncode != 0:
            return file_api_error(
                result.stderr.strip() or "Backup konnte nicht erstellt werden.",
                500,
            )
        return jsonify({"ok": True, "name": result.stdout.strip()})
    except (OSError, subprocess.TimeoutExpired) as exc:
        return file_api_error(str(exc), 500)


@app.post("/api/terminal/execute")
@authentication_required("terminal_access")
def api_terminal_execute():
    if not bool(g.auth_user["is_admin"]):
        return jsonify({
            "ok": False,
            "error": "Das Web-Terminal ist ausschließlich für Administratoren verfügbar.",
            "code": "administrator_required",
        }), 403

    payload = request.get_json(silent=True) or {}
    command = str(payload.get("command") or "").strip()
    cwd = str(payload.get("cwd") or TERMINAL_HOME)

    if not command:
        return jsonify({
            "ok": False,
            "error": "Bitte einen Befehl eingeben.",
        }), 400

    if len(command) > TERMINAL_MAX_COMMAND_LENGTH or "\x00" in command:
        return jsonify({
            "ok": False,
            "error": "Der Befehl ist zu lang oder enthält ungültige Zeichen.",
        }), 400

    if len(cwd) > 1024 or "\x00" in cwd or not cwd.startswith("/"):
        return jsonify({
            "ok": False,
            "error": "Ungültiges Arbeitsverzeichnis.",
        }), 400

    if not terminal_slot.acquire(blocking=False):
        return jsonify({
            "ok": False,
            "error": "Im Terminal läuft bereits ein Befehl.",
        }), 429

    try:
        result = execute_terminal_command(command, cwd)
        return jsonify({"ok": True, **result})
    except FileNotFoundError:
        return jsonify({
            "ok": False,
            "error": "Der abgesicherte Terminal-Benutzer ist noch nicht eingerichtet.",
        }), 503
    except Exception as exc:
        return jsonify({
            "ok": False,
            "error": f"Terminal konnte nicht gestartet werden: {exc}",
        }), 500
    finally:
        cleanup_terminal_processes()
        terminal_slot.release()


@app.get("/api/history")
@authentication_required("dashboard_view")
def api_history():
    cutoff = int(time.time()) - 24 * 60 * 60

    with history_lock:
        points = [
            point
            for point in history_points
            if isinstance(point.get("ts"), (int, float))
            and point["ts"] >= cutoff
        ]

    return jsonify({
        "history": points,
        "interval_seconds": HISTORY_INTERVAL_SECONDS,
        "max_points": HISTORY_MAX_POINTS,
    })


@app.get("/")
def web_index():
    return send_from_directory(WEB_DIR, "index.html")


@app.get("/<path:asset_path>")
def web_asset(asset_path):
    requested_file = WEB_DIR / asset_path

    if requested_file.is_file():
        return send_from_directory(WEB_DIR, asset_path)

    return send_from_directory(WEB_DIR, "index.html")


@app.post("/api/reboot")
@authentication_required("system_control")
def api_reboot():
    def delayed_reboot():
        time.sleep(1.5)
        subprocess.run(
            ["systemctl", "reboot"],
            check=False,
        )

    threading.Thread(
        target=delayed_reboot,
        daemon=True,
    ).start()

    return jsonify({
        "ok": True,
        "message": "Raspberry Pi wird neu gestartet",
    })


@app.post("/api/service/<service>/restart")
@authentication_required("system_control")
def api_restart_service(service):
    service_map = {
        "samba": "smbd",
        "tailscale": "tailscaled",
    }

    systemd_service = service_map.get(service)

    if systemd_service is None:
        return jsonify({
            "ok": False,
            "error": "Unbekannter Dienst",
        }), 404

    code, _, stderr = run_command(
        ["systemctl", "restart", systemd_service],
        timeout=15,
    )

    if code != 0:
        return jsonify({
            "ok": False,
            "error": stderr or "Dienst konnte nicht neu gestartet werden",
        }), 500

    return jsonify({
        "ok": True,
        "service": service,
        "active": service_running(systemd_service),
    })




@app.get("/api/benchmark/history")
@authentication_required("dashboard_view")
def api_benchmark_history():
    return jsonify({
        "history": benchmark_history[
            -BENCHMARK_HISTORY_MAX_POINTS:
        ],
        "max_points": BENCHMARK_HISTORY_MAX_POINTS,
    })


@app.post("/api/benchmark/cpu")
@authentication_required("benchmark_run")
def api_cpu_benchmark():
    global last_benchmark_finished

    now = time.monotonic()
    remaining = (
        BENCHMARK_COOLDOWN_SECONDS
        - (now - last_benchmark_finished)
    )

    if remaining > 0:
        return jsonify({
            "ok": False,
            "error": (
                "Benchmark-Cooldown aktiv. "
                f"Noch {int(remaining) + 1} Sekunden."
            ),
        }), 429

    if not benchmark_lock.acquire(blocking=False):
        return jsonify({
            "ok": False,
            "error": "Es läuft bereits ein Benchmark.",
        }), 409

    try:
        result = perform_cpu_benchmark()
        return jsonify(result)
    except Exception as exc:
        return jsonify({
            "ok": False,
            "error": str(exc),
        }), 500
    finally:
        last_benchmark_finished = time.monotonic()
        benchmark_lock.release()


if __name__ == "__main__":
    BASE_DIR.mkdir(parents=True, exist_ok=True)
    initialize_auth_database()
    load_history_from_disk()
    load_benchmark_from_disk()
    load_benchmark_history_from_disk()

    monitor = threading.Thread(
        target=monitor_loop,
        daemon=True,
        name="pi-control-monitor",
    )
    monitor.start()

    app.run(
        host="0.0.0.0",
        port=PORT,
        debug=False,
        threaded=True,
        use_reloader=False,
    )
