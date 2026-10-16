#!/usr/bin/env python3
"""Loopback-only, token-protected API for the Pi-Control PC helper."""
from __future__ import annotations

import argparse
import json
import os
import platform
import secrets
import subprocess
import sys
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

PORT = 8765
ALLOWED_ORIGINS = {"https://pi-control-dashboard.steindlsimon12.workers.dev"}
MAX_BODY = 4096
MAX_FILE_BYTES = 1_000_000
MAX_DIRECTORY_ENTRIES = 300

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
        if host not in {"127.0.0.1:8765", "localhost:8765"}:
            self.send_json(403, {"ok": False, "error": "Nur lokale Host-Header sind erlaubt."})
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
                "allowed_actions": ["status", "diff", "read", "list", "tests", "open"],
            })
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
        if parsed.path == "/v1/open":
            try:
                app_name = str(body.get("app", ""))
                launch_app(app_name, self.workspace)
                self.send_json(200, {"ok": True, "opened": app_name})
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
    args = parser.parse_args()
    workspace = Path(args.workspace).expanduser().resolve()
    access_root = Path(args.access_root).expanduser().resolve()
    if not workspace.is_dir():
        print("Projektordner nicht gefunden.", file=sys.stderr)
        return 2
    if not access_root.is_dir():
        print("Freigegebener Datei-Stammordner nicht gefunden.", file=sys.stderr)
        return 2
    token = load_or_create_token()
    server = ThreadingHTTPServer(("127.0.0.1", PORT), AgentHandler)
    server.workspace = workspace
    server.access_root = access_root
    server.token = token
    print(f"Pi-Control PC-Agent läuft nur lokal auf http://127.0.0.1:{PORT}")
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
