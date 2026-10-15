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
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

PORT = 8765
ALLOWED_ORIGINS = {
    "https://pi-control-dashboard.steindlsimon12.workers.dev",
}
ALLOWED_APPS = {"editor", "browser", "file-manager"}
MAX_BODY = 4096


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


def safe_file(workspace: Path, relative: str) -> Path:
    target = (workspace / relative).resolve()
    if target != workspace and workspace not in target.parents:
        raise ValueError("Zugriff außerhalb des Projektordners ist gesperrt.")
    if not target.is_file():
        raise ValueError("Datei nicht gefunden.")
    if target.stat().st_size > 256_000:
        raise ValueError("Datei ist zu groß (Limit 256 KB).")
    return target


def git_output(workspace: Path, *args: str) -> dict:
    try:
        result = subprocess.run(
            ["git", *args],
            cwd=workspace,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=15,
            check=False,
        )
        return {"ok": result.returncode == 0, "exit_code": result.returncode, "output": result.stdout[:12000]}
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"ok": False, "error": str(exc)[:300]}


def launch_app(app_name: str, workspace: Path) -> None:
    system = platform.system()
    if system == "Windows":
        commands = {"editor": ["notepad.exe"], "browser": ["cmd", "/c", "start", ""], "file-manager": ["explorer.exe", str(workspace)]}
    elif system == "Linux":
        commands = {"editor": ["xdg-open", str(workspace)], "browser": ["xdg-open", "https://pi-control-dashboard.steindlsimon12.workers.dev"], "file-manager": ["xdg-open", str(workspace)]}
    elif system == "Darwin":
        commands = {"editor": ["open", "-t"], "browser": ["open", "https://pi-control-dashboard.steindlsimon12.workers.dev"], "file-manager": ["open", str(workspace)]}
    else:
        raise ValueError("Dieses Betriebssystem wird nicht unterstützt.")
    if app_name not in commands:
        raise ValueError("Programm ist nicht freigegeben.")
    subprocess.Popen(commands[app_name], cwd=workspace, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


class AgentHandler(BaseHTTPRequestHandler):
    server_version = "PiControlLocalAgent/0.1"

    @property
    def workspace(self) -> Path:
        return self.server.workspace

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
        self.wfile.write(data)

    def do_OPTIONS(self):
        origin = self.headers.get("Origin", "")
        if origin not in ALLOWED_ORIGINS:
            self.send_json(403, {"ok": False, "error": "Origin nicht erlaubt."})
            return
        self.send_json(204, {"ok": True})

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
        if parsed.path == "/v1/status":
            self.send_json(200, {
                "ok": True,
                "agent": "Pi-Control PC-Agent",
                "os": platform.system(),
                "workspace": str(self.workspace),
                "git_available": subprocess.run(
                    ["git", "--version"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False
                ).returncode == 0,
                "allowed_actions": ["status", "diff", "read", "tests", "open"],
            })
            return
        if parsed.path == "/v1/git/status":
            self.send_json(200, git_output(self.workspace, "status", "--short", "--branch"))
            return
        if parsed.path == "/v1/git/diff":
            self.send_json(200, git_output(self.workspace, "diff", "--"))
            return
        if parsed.path == "/v1/file":
            relative = parse_qs(parsed.query).get("path", [""])[0]
            try:
                target = safe_file(self.workspace, relative)
                self.send_json(200, {"ok": True, "path": relative, "content": target.read_text(encoding="utf-8")})
            except (OSError, UnicodeError, ValueError) as exc:
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
                    [sys.executable, str(test_file)],
                    cwd=self.workspace,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    timeout=180,
                    check=False,
                )
                self.send_json(200, {"ok": result.returncode == 0, "exit_code": result.returncode, "output": result.stdout[-10000:]})
            except (OSError, subprocess.TimeoutExpired) as exc:
                self.send_json(500, {"ok": False, "error": str(exc)[:300]})
            return
        self.send_json(404, {"ok": False, "error": "Route nicht gefunden."})


def main() -> int:
    parser = argparse.ArgumentParser(description="Loopback-only Pi-Control local API")
    parser.add_argument("--workspace", required=True)
    args = parser.parse_args()
    workspace = Path(args.workspace).expanduser().resolve()
    if not workspace.is_dir():
        print("Projektordner nicht gefunden.", file=sys.stderr)
        return 2
    token = load_or_create_token()
    server = ThreadingHTTPServer(("127.0.0.1", PORT), AgentHandler)
    server.workspace = workspace
    server.token = token
    print(f"Pi-Control PC-Agent läuft nur lokal auf http://127.0.0.1:{PORT}")
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
