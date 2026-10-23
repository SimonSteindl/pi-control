#!/usr/bin/env python3
"""Loopback-only, token-protected API for the Pi-Control PC helper."""
from __future__ import annotations

import argparse
import json
import os
import platform
import secrets
import shutil
import subprocess
import time
import sys
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

PORT = 8765
ALLOWED_ORIGINS = {"https://pi-control-dashboard.steindlsimon12.workers.dev"}
MAX_BODY = 1_100_000
MAX_FILE_BYTES = 1_000_000
MAX_DIRECTORY_ENTRIES = 300
MAX_WRITE_BYTES = 1_000_000
MAX_COMMAND_SECONDS = 120
MAX_COMMAND_OUTPUT_BYTES = 20_000
# Only exact, read-only diagnostic commands are allowed.
ALLOWED_COMMANDS = {
    ("whoami",),
    ("uname", "-a"),
    ("uptime",),
    ("df", "-h"),
    ("free", "-h"),
}

# Keep private credentials out of routine AI file access.
SENSITIVE_PARTS = {
    ".ssh", ".gnupg", ".pki", ".password-store",
    "keyrings", "wallets",
}
SENSITIVE_NAMES = {
    ".env", ".env.local", ".netrc", ".npmrc", ".pypirc",
    "credentials", "credentials.json", "token",
}
SENSITIVE_SUFFIXES = {".pem", ".key", ".p12", ".pfx"}


def token_path() -> Path:
    return Path.home() / ".pi-control-agent" / "token"


def load_or_create_token() -> str:
    path = token_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        token = path.read_text(encoding="utf-8").strip()
        if len(token) >= 48:
            return token
    except OSError:
        pass
    token = secrets.token_urlsafe(48)
    fd, temporary = tempfile.mkstemp(prefix="token-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(token + "\n")
        try:
            os.chmod(temporary, 0o600)
        except OSError:
            pass
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
    return token


def resolve_user_path(access_root: Path, supplied: str) -> Path:
    if not supplied.strip():
        raise ValueError("Bitte einen Dateipfad angeben.")
    candidate = Path(supplied).expanduser()
    if not candidate.is_absolute():
        candidate = access_root / candidate
    if candidate.is_symlink():
        raise ValueError("Symbolische Links dürfen nicht verändert werden.")
    target = candidate.resolve()
    if target != access_root and access_root not in target.parents:
        raise ValueError("Zugriff außerhalb des freigegebenen Benutzerordners ist gesperrt.")
    relative_parts = target.relative_to(access_root).parts
    if any(part.lower() in SENSITIVE_PARTS for part in relative_parts):
        raise ValueError("Dieser Ordner enthält private Zugangsdaten und ist standardmäßig gesperrt.")
    if target.name.lower() in SENSITIVE_NAMES or target.suffix.lower() in SENSITIVE_SUFFIXES:
        raise ValueError("Diese Datei kann Zugangsdaten oder private Schlüssel enthalten und ist standardmäßig gesperrt.")
    return target


def safe_file(access_root: Path, supplied: str) -> Path:
    target = resolve_user_path(access_root, supplied)
    if not target.is_file():
        raise ValueError("Datei nicht gefunden.")
    if target.stat().st_size > MAX_FILE_BYTES:
        raise ValueError("Datei ist zu groß (Limit 1 MB).")
    return target


def git_output(workspace: Path, *args: str) -> dict:
    try:
        result = subprocess.run(
            ["git", *args], cwd=workspace, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=15, check=False,
        )
        return {"ok": result.returncode == 0, "exit_code": result.returncode, "output": result.stdout[:12000]}
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"ok": False, "error": str(exc)[:300]}


def launch_app(app_name: str, workspace: Path) -> None:
    system = platform.system()
    if system == "Windows":
        commands = {
            "editor": ["notepad.exe"],
            "browser": ["cmd", "/c", "start", "", "https://pi-control-dashboard.steindlsimon12.workers.dev"],
            "file-manager": ["explorer.exe", str(workspace)],
        }
    elif system == "Linux":
        commands = {
            "editor": ["xdg-open", str(workspace)],
            "browser": ["xdg-open", "https://pi-control-dashboard.steindlsimon12.workers.dev"],
            "file-manager": ["xdg-open", str(workspace)],
        }
    elif system == "Darwin":
        commands = {
            "editor": ["open", "-t"],
            "browser": ["open", "https://pi-control-dashboard.steindlsimon12.workers.dev"],
            "file-manager": ["open", str(workspace)],
        }
    else:
        raise ValueError("Dieses Betriebssystem wird nicht unterstützt.")
    if app_name not in commands:
        raise ValueError("Programm ist nicht freigegeben.")
    subprocess.Popen(commands[app_name], cwd=workspace, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


class AgentHandler(BaseHTTPRequestHandler):
    server_version = "PiControlLocalAgent/0.2"

    @property
    def workspace(self) -> Path:
        return self.server.workspace

    @property
    def access_root(self) -> Path:
        return self.server.access_root

    @property
    def memory(self):
        return self.server.memory

    def log_message(self, fmt, *args):
        # Never log authorization headers or request bodies.
        print("Pi-Control-Agent:", fmt % args)

    def send_json(self, status: int, payload: dict) -> None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        origin = self.headers.get("Origin", "")
        if origin in ALLOWED_ORIGINS:
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Vary", "Origin")
            self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if status != 204:
            self.wfile.write(data)

    def do_OPTIONS(self):
        origin = self.headers.get("Origin", "")
        if origin not in ALLOWED_ORIGINS:
            self.send_json(403, {"ok": False, "error": "Origin nicht erlaubt."})
            return
        self.send_json(204, {})

    def authorized(self) -> bool:
        host = self.headers.get("Host", "")
        allowed_hosts = {f"{self.server.bind_host}:{PORT}", "127.0.0.1:8765", "localhost:8765"}
        if host not in allowed_hosts:
            self.send_json(403, {"ok": False, "error": "Host-Header nicht erlaubt."})
            return False
        client_ip = self.client_address[0]
        if client_ip not in self.server.allowed_clients:
            self.send_json(403, {"ok": False, "error": "Client-IP ist nicht freigegeben."})
            return False
        supplied = self.headers.get("Authorization", "")
        if not supplied.startswith("Bearer ") or not secrets.compare_digest(supplied[7:].strip(), self.server.token):
            self.send_json(401, {"ok": False, "error": "Agent-Token fehlt oder ist ungültig."})
            return False
        return True

    def do_GET(self):
        if not self.authorized():
            return
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        if parsed.path == "/v1/status":
            self.send_json(200, {
                "ok": True,
                "agent": "Pi-Control PC-Agent",
                "os": platform.system(),
                "workspace": str(self.workspace),
                "access_root": str(self.access_root),
                "git_available": subprocess.run(
                    ["git", "--version"], stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL, check=False,
                ).returncode == 0,
                "allowed_actions": ["status", "diff", "read", "list", "tests", "open", "write_file", "trash_file", "run_command", "memory", "run_safe_plan"],
                "memory_enabled": True,
                "bind_host": self.server.bind_host,
                "allowed_clients": sorted(self.server.allowed_clients),
            })
            return
        if parsed.path == "/v1/memory/current":
            self.send_json(200, {"ok": True, **self.memory.resume_context()})
            return
        if parsed.path == "/v1/memory/tasks":
            self.send_json(200, {"ok": True, "tasks": self.memory.recent_tasks()})
            return
        if parsed.path == "/v1/memory/task":
            task_id = query.get("id", [""])[0]
            task = self.memory.get_task(task_id) if task_id else None
            if task is None:
                self.send_json(404, {"ok": False, "error": "Aufgabe nicht gefunden."})
                return
            self.send_json(200, {"ok": True, "task": task, "events": self.memory.task_events(task_id)})
            return
        if parsed.path == "/v1/git/status":
            self.send_json(200, git_output(self.workspace, "status", "--short", "--branch"))
            return
        if parsed.path == "/v1/git/diff":
            self.send_json(200, git_output(self.workspace, "diff", "--"))
            return
        if parsed.path == "/v1/file":
            supplied = query.get("path", [""])[0]
            try:
                target = safe_file(self.access_root, supplied)
                self.send_json(200, {
                    "ok": True, "path": str(target),
                    "content": target.read_text(encoding="utf-8"),
                })
            except (OSError, UnicodeError, ValueError) as exc:
                self.send_json(400, {"ok": False, "error": str(exc)})
            return
        if parsed.path == "/v1/files":
            supplied = query.get("path", ["."])[0]
            try:
                directory = resolve_user_path(self.access_root, supplied)
                if not directory.is_dir():
                    raise ValueError("Der Pfad ist kein Ordner.")
                entries = []
                with os.scandir(directory) as iterator:
                    for entry in iterator:
                        if len(entries) >= MAX_DIRECTORY_ENTRIES:
                            break
                        try:
                            child = resolve_user_path(self.access_root, entry.path)
                            if child.is_dir():
                                kind = "directory"
                            elif child.is_file():
                                kind = "file"
                            else:
                                continue
                            entries.append({"name": entry.name, "type": kind})
                        except (OSError, ValueError):
                            continue
                entries.sort(key=lambda item: (item["type"] != "directory", item["name"].lower()))
                self.send_json(200, {
                    "ok": True, "path": str(directory), "entries": entries,
                    "truncated": len(entries) >= MAX_DIRECTORY_ENTRIES,
                })
            except (OSError, ValueError) as exc:
                self.send_json(400, {"ok": False, "error": str(exc)})
            return
        self.send_json(404, {"ok": False, "error": "Route nicht gefunden."})

    def do_POST(self):
        if not self.authorized():
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length > MAX_BODY:
            self.send_json(413, {"ok": False, "error": "Anfrage ist zu groß."})
            return
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
        except (json.JSONDecodeError, UnicodeDecodeError):
            self.send_json(400, {"ok": False, "error": "Ungültiges JSON."})
            return
        if not isinstance(body, dict):
            self.send_json(400, {"ok": False, "error": "JSON-Objekt erwartet."})
            return
        parsed = urlparse(self.path)
        if parsed.path == "/v1/agent/run":
            try:
                # Import after main() adds the repository root to sys.path.
                from pc_agent.task_runner import PlanValidationError, run_plan

                title = body.get("title")
                goal = body.get("goal")
                steps = body.get("steps")

                def execute_safe_step(step):
                    action = step["action"]
                    if action == "status":
                        git_available = subprocess.run(
                            ["git", "--version"], stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, check=False,
                        ).returncode == 0
                        return {"ok": True, "os": platform.system(),
                                "workspace": str(self.workspace),
                                "git_available": git_available}
                    if action == "git_status":
                        return git_output(self.workspace, "status", "--short", "--branch")
                    if action == "git_diff":
                        return git_output(self.workspace, "diff", "--")
                    if action == "read_file":
                        target = safe_file(self.access_root, step["path"])
                        content = target.read_text(encoding="utf-8")
                        output_limit = 12_000
                        return {"ok": True, "path": str(target),
                                "content": content[:output_limit],
                                "truncated": len(content) > output_limit}
                    if action == "list_files":
                        directory = resolve_user_path(self.access_root, step["path"])
                        if not directory.is_dir():
                            raise ValueError("Der Pfad ist kein Ordner.")
                        entries = []
                        with os.scandir(directory) as iterator:
                            for entry in iterator:
                                if len(entries) >= MAX_DIRECTORY_ENTRIES:
                                    break
                                try:
                                    child = resolve_user_path(self.access_root, entry.path)
                                    if child.is_dir():
                                        kind = "directory"
                                    elif child.is_file():
                                        kind = "file"
                                    else:
                                        continue
                                    entries.append({"name": entry.name, "type": kind})
                                except (OSError, ValueError):
                                    continue
                        entries.sort(key=lambda item: (item["type"] != "directory", item["name"].lower()))
                        return {"ok": True, "path": str(directory), "entries": entries,
                                "truncated": len(entries) >= MAX_DIRECTORY_ENTRIES}
                    if action == "tests":
                        test_file = self.workspace / "server" / "test_ai_memory.py"
                        if not test_file.is_file():
                            return {"ok": False, "error": "Kein bekannter Test gefunden."}
                        project_python = self.workspace / ".venv" / "bin" / "python"
                        test_python = (
                            str(project_python)
                            if project_python.is_file()
                            else sys.executable
                        )
                        result = subprocess.run(
                            [test_python, str(test_file)], cwd=self.workspace,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=180, check=False,
                        )
                        return {"ok": result.returncode == 0, "exit_code": result.returncode,
                                "output": result.stdout[-10000:]}
                    raise ValueError("Aktion ist nicht freigegeben.")

                result = run_plan(self.memory, title, goal, steps, execute_safe_step)
                self.send_json(200 if result.get("ok") else 409, result)
            except PlanValidationError as exc:
                self.send_json(400, {"ok": False, "error": str(exc)})
            except (OSError, UnicodeError, ValueError, TypeError) as exc:
                self.send_json(400, {"ok": False, "error": str(exc)[:300]})
            return
        if parsed.path == "/v1/open":
            try:
                app_name = str(body.get("app", ""))
                launch_app(app_name, self.workspace)
                self.send_json(200, {"ok": True, "opened": app_name})
            except (OSError, ValueError) as exc:
                self.send_json(400, {"ok": False, "error": str(exc)[:300]})
            return
        if parsed.path == "/v1/memory/task/start":
            try:
                title = body.get("title")
                goal = body.get("goal")
                if not isinstance(title, str) or not title.strip() or not isinstance(goal, str) or not goal.strip():
                    raise ValueError("title und goal müssen Text sein.")
                if len(title) > 200 or len(goal) > 4000:
                    raise ValueError("Titel oder Ziel ist zu lang.")
                task = self.memory.start_task(title, goal)
                self.send_json(201, {"ok": True, "task": task})
            except (OSError, ValueError) as exc:
                self.send_json(400, {"ok": False, "error": str(exc)[:300]})
            return
        if parsed.path == "/v1/memory/task/step":
            try:
                task_id = body.get("task_id")
                step = body.get("step")
                message = body.get("message")
                details = body.get("details", {})
                status = body.get("status", "in_progress")
                if not all(isinstance(value, str) and value.strip() for value in (task_id, step, message)):
                    raise ValueError("task_id, step und message müssen Text sein.")
                if not isinstance(details, dict):
                    raise ValueError("details muss ein Objekt sein.")
                if len(message) > 4000 or len(step) > 200:
                    raise ValueError("Schritt oder Meldung ist zu lang.")
                task = self.memory.record_step(
                    task_id, step, message, details=details, status=status,
                    summary=body.get("summary"), next_step=body.get("next_step"),
                )
                self.send_json(200, {"ok": True, "task": task})
            except KeyError as exc:
                self.send_json(404, {"ok": False, "error": str(exc)})
            except (OSError, ValueError, TypeError) as exc:
                self.send_json(400, {"ok": False, "error": str(exc)[:300]})
            return
        if parsed.path == "/v1/file/write":
            try:
                if body.get("approved") is not True:
                    raise PermissionError("Dateiänderung benötigt eine ausdrückliche Bestätigung.")
                supplied = body.get("path")
                content = body.get("content")
                if not isinstance(supplied, str) or not isinstance(content, str):
                    raise ValueError("path und content müssen Text sein.")
                encoded = content.encode("utf-8")
                if len(encoded) > MAX_WRITE_BYTES:
                    raise ValueError("Datei ist größer als das Limit von 1 MB.")
                target = resolve_user_path(self.access_root, supplied)
                if target == self.access_root:
                    raise ValueError("Der freigegebene Stammordner kann nicht überschrieben werden.")
                if target.exists() and not target.is_file():
                    raise ValueError("Ziel ist keine normale Datei.")
                parent = target.parent.resolve()
                if parent != self.access_root and self.access_root not in parent.parents:
                    raise ValueError("Zielordner liegt außerhalb des freigegebenen Bereichs.")
                if not parent.is_dir():
                    raise ValueError("Der Zielordner existiert nicht.")
                backup_path = None
                if target.exists():
                    backup_root = Path.home() / ".pi-control-agent" / "backups"
                    backup_root.mkdir(parents=True, exist_ok=True, mode=0o700)
                    try:
                        os.chmod(backup_root, 0o700)
                    except OSError:
                        pass
                    backup_path = backup_root / f"{int(time.time())}-{secrets.token_hex(4)}-{target.name}"
                    shutil.copy2(target, backup_path)
                fd, temporary = tempfile.mkstemp(prefix=".pi-control-write-", dir=parent)
                try:
                    with os.fdopen(fd, "wb") as handle:
                        handle.write(encoded)
                    if target.exists():
                        os.chmod(temporary, target.stat().st_mode & 0o777)
                    os.replace(temporary, target)
                finally:
                    try:
                        os.unlink(temporary)
                    except FileNotFoundError:
                        pass
                self.send_json(200, {"ok": True, "path": str(target), "bytes_written": len(encoded), "backup": str(backup_path) if backup_path else None})
            except PermissionError as exc:
                self.send_json(403, {"ok": False, "error": str(exc)})
            except (OSError, UnicodeError, ValueError) as exc:
                self.send_json(400, {"ok": False, "error": str(exc)[:300]})
            return
        if parsed.path == "/v1/file/delete":
            try:
                if body.get("approved") is not True:
                    raise PermissionError("Löschen benötigt eine ausdrückliche Bestätigung.")
                supplied = body.get("path")
                if not isinstance(supplied, str):
                    raise ValueError("path muss Text sein.")
                target = resolve_user_path(self.access_root, supplied)
                if target == self.access_root:
                    raise ValueError("Der freigegebene Stammordner kann nicht gelöscht werden.")
                if not target.exists() or not (target.is_file() or target.is_dir()):
                    raise ValueError("Ziel nicht gefunden oder nicht unterstützt.")
                trash_root = Path.home() / ".pi-control-agent" / "trash"
                trash_root.mkdir(parents=True, exist_ok=True, mode=0o700)
                try:
                    os.chmod(trash_root, 0o700)
                except OSError:
                    pass
                trash_target = trash_root / f"{int(time.time())}-{secrets.token_hex(4)}-{target.name}"
                shutil.move(str(target), str(trash_target))
                self.send_json(200, {"ok": True, "original_path": str(target), "trash_path": str(trash_target)})
            except PermissionError as exc:
                self.send_json(403, {"ok": False, "error": str(exc)})
            except (OSError, ValueError) as exc:
                self.send_json(400, {"ok": False, "error": str(exc)[:300]})
            return
        if parsed.path == "/v1/command":
            try:
                if body.get("approved") is not True:
                    raise PermissionError("Befehle benötigen eine ausdrückliche Bestätigung.")
                command = body.get("command")
                if (not isinstance(command, list) or not command or len(command) > 100
                        or any(not isinstance(arg, str) or len(arg) > 2000 for arg in command)):
                    raise ValueError("command muss eine Liste kurzer Textargumente sein.")
                if tuple(command) not in ALLOWED_COMMANDS:
                    raise PermissionError(
                        "Dieser Befehl ist nicht freigegeben."
                    )
                timeout = body.get("timeout", 30)
                if isinstance(timeout, bool) or not isinstance(timeout, int) or not 1 <= timeout <= MAX_COMMAND_SECONDS:
                    raise ValueError(f"timeout muss zwischen 1 und {MAX_COMMAND_SECONDS} Sekunden liegen.")
                cwd_value = body.get("cwd", str(self.workspace))
                if not isinstance(cwd_value, str):
                    raise ValueError("cwd muss Text sein.")
                cwd = resolve_user_path(self.access_root, cwd_value)
                if not cwd.is_dir():
                    raise ValueError("Arbeitsverzeichnis ist kein Ordner.")
                result = subprocess.run(
                    command, cwd=cwd, text=True, stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT, timeout=timeout, check=False, shell=False,
                )
                output = result.stdout[-MAX_COMMAND_OUTPUT_BYTES:]
                self.send_json(200, {"ok": result.returncode == 0, "exit_code": result.returncode, "output": output, "truncated": len(result.stdout) > MAX_COMMAND_OUTPUT_BYTES})
            except PermissionError as exc:
                self.send_json(403, {"ok": False, "error": str(exc)})
            except subprocess.TimeoutExpired as exc:
                output = exc.stdout or b""
                if isinstance(output, bytes):
                    output = output.decode("utf-8", errors="replace")
                self.send_json(408, {"ok": False, "error": "Befehl hat das Zeitlimit überschritten.", "output": str(output)[-MAX_COMMAND_OUTPUT_BYTES:]})
            except (OSError, ValueError) as exc:
                self.send_json(400, {"ok": False, "error": str(exc)[:300]})
            return
        if parsed.path == "/v1/tests":
            test_file = self.workspace / "server" / "test_ai_memory.py"
            if not test_file.is_file():
                self.send_json(404, {"ok": False, "error": "Kein bekannter Test gefunden."})
                return
            try:
                result = subprocess.run(
                    [sys.executable, str(test_file)], cwd=self.workspace,
                    text=True, stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT, timeout=180, check=False,
                )
                self.send_json(200, {
                    "ok": result.returncode == 0, "exit_code": result.returncode,
                    "output": result.stdout[-10000:],
                })
            except (OSError, subprocess.TimeoutExpired) as exc:
                self.send_json(500, {"ok": False, "error": str(exc)[:300]})
            return
        self.send_json(404, {"ok": False, "error": "Route nicht gefunden."})


def main() -> int:
    parser = argparse.ArgumentParser(description="Loopback-only Pi-Control local API")
    parser.add_argument("--workspace", required=True, help="Pi-Control-Projektordner für Git- und Testfunktionen")
    parser.add_argument("--access-root", default=str(Path.home()), help="Freigegebener Datei-Stammordner; Standard ist das Benutzerverzeichnis")
    parser.add_argument("--bind-host", default="127.0.0.1", help="Listener-Adresse; Standard bleibt nur lokal erreichbar")
    parser.add_argument("--allowed-client", action="append", default=[], help="Exakte erlaubte Client-IP; bei nicht-lokalem Listener verpflichtend")
    args = parser.parse_args()
    workspace = Path(args.workspace).expanduser().resolve()
    access_root = Path(args.access_root).expanduser().resolve()
    if not workspace.is_dir():
        print("Projektordner nicht gefunden.", file=sys.stderr)
        return 2
    if not access_root.is_dir():
        print("Freigegebener Datei-Stammordner nicht gefunden.", file=sys.stderr)
        return 2
    bind_host = args.bind_host.strip()
    try:
        import ipaddress
        bind_ip = ipaddress.ip_address(bind_host)
        is_loopback = bind_ip.is_loopback
        allowed_clients = set(args.allowed_client)
        for client in allowed_clients:
            ipaddress.ip_address(client)
    except ValueError:
        print("Listener- und Client-Adressen müssen gültige IP-Adressen sein.", file=sys.stderr)
        return 2
    if not is_loopback and not allowed_clients:
        print("Ein Netzwerk-Listener braucht mindestens eine --allowed-client-IP.", file=sys.stderr)
        return 2
    if is_loopback:
        allowed_clients.update({"127.0.0.1", "::1"})
    # Make the repository-local memory package importable regardless of cwd.
    sys.path.insert(0, str(workspace))
    try:
        from pc_agent.memory import AgentMemory
        memory = AgentMemory()
    except Exception as exc:
        print(f"PC-Agent-Speicher konnte nicht gestartet werden: {exc}", file=sys.stderr)
        return 2
    token = load_or_create_token()
    server = ThreadingHTTPServer((bind_host, PORT), AgentHandler)
    server.memory = memory
    server.workspace = workspace
    server.access_root = access_root
    server.token = token
    server.bind_host = bind_host
    server.allowed_clients = allowed_clients
    print(f"Pi-Control PC-Agent lauscht auf http://{bind_host}:{PORT}")
    print(f"Erlaubte Clients: {', '.join(sorted(allowed_clients))}")
    print(f"Projekt: {workspace}")
    print(f"Dateizugriff: {access_root} (Zugangsdaten-/Schlüsselpfade sind gesperrt)")
    print(f"Token-Datei: {token_path()}")
    print("Stoppen mit Strg+C. Nicht öffentlich ins Internet freigeben.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nAgent beendet.")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
