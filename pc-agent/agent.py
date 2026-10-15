#!/usr/bin/env python3
"""Local, cross-platform helper for Pi-Control development.

This first version deliberately exposes only an allowlist of operations. It does
not run arbitrary shell commands or accept remote network connections.
"""
from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
import sys
import webbrowser
from pathlib import Path

DEFAULT_WORKSPACE = Path(__file__).resolve().parents[1]
WORKSPACE = Path(os.environ.get("PI_CONTROL_WORKSPACE", str(DEFAULT_WORKSPACE))).expanduser().resolve()
ALLOWED_PROGRAMS = {
    "windows": {
        "editor": ["notepad.exe"],
        "browser": ["cmd", "/c", "start", ""],
    },
    "linux": {
        "editor": ["xdg-open"],
        "browser": ["xdg-open"],
        "file-manager": ["xdg-open"],
    },
    "darwin": {
        "editor": ["open", "-t"],
        "browser": ["open"],
        "file-manager": ["open"],
    },
}


def run(args: list[str], *, timeout: int = 120) -> int:
    try:
        result = subprocess.run(
            args,
            cwd=WORKSPACE,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        print(f"Fehler: {exc}", file=sys.stderr)
        return 1
    print(result.stdout, end="" if result.stdout.endswith("\n") or not result.stdout else "\n")
    return result.returncode


def inside_workspace(relative_path: str) -> Path:
    target = (WORKSPACE / relative_path).resolve()
    if target != WORKSPACE and WORKSPACE not in target.parents:
        raise ValueError("Zugriff außerhalb des Pi-Control-Projektordners ist gesperrt.")
    if not target.is_file():
        raise ValueError(f"Datei nicht gefunden: {relative_path}")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="Sicherer Pi-Control-PC-Helfer (Windows/Linux/macOS)")
    parser.add_argument("action", choices=["info", "status", "diff", "tests", "read", "open", "url"])
    parser.add_argument("target", nargs="?", help="Relativer Dateipfad, Programmname oder URL")
    parser.add_argument("--workspace", help="Pi-Control-Projektordner überschreiben")
    parsed = parser.parse_args()

    global WORKSPACE
    if parsed.workspace:
        WORKSPACE = Path(parsed.workspace).expanduser().resolve()

    if not WORKSPACE.is_dir():
        print(f"Projektordner existiert nicht: {WORKSPACE}", file=sys.stderr)
        return 2

    if parsed.action == "info":
        print(f"System: {platform.system()} {platform.release()}")
        print(f"Python: {platform.python_version()}")
        print(f"Projekt: {WORKSPACE}")
        print(f"Git: {shutil.which('git') or 'nicht installiert'}")
        return 0
    if parsed.action == "status":
        return run(["git", "status", "--short", "--branch"])
    if parsed.action == "diff":
        return run(["git", "diff", "--"])
    if parsed.action == "tests":
        test_file = WORKSPACE / "server" / "test_ai_memory.py"
        if test_file.is_file():
            return run([sys.executable, str(test_file)], timeout=180)
        print("Kein bekannter Server-Test gefunden. Es wurde nichts ausgeführt.")
        return 2
    if parsed.action == "read":
        if not parsed.target:
            parser.error("read benötigt einen relativen Dateipfad")
        try:
            target = inside_workspace(parsed.target)
            print(target.read_text(encoding="utf-8"))
            return 0
        except (OSError, UnicodeError, ValueError) as exc:
            print(f"Fehler: {exc}", file=sys.stderr)
            return 2
    if parsed.action == "open":
        if not parsed.target:
            parser.error("open benötigt editor, browser oder file-manager")
        os_key = {"Windows": "windows", "Linux": "linux", "Darwin": "darwin"}.get(platform.system())
        programs = ALLOWED_PROGRAMS.get(os_key or "", {})
        if parsed.target not in programs:
            print(f"Programm nicht erlaubt. Verfügbar: {', '.join(programs) or 'keine'}", file=sys.stderr)
            return 2
        command = programs[parsed.target]
        try:
            subprocess.Popen(command + ([str(WORKSPACE)] if parsed.target == "file-manager" else []), cwd=WORKSPACE)
            return 0
        except OSError as exc:
            print(f"Programm konnte nicht geöffnet werden: {exc}", file=sys.stderr)
            return 1
    if parsed.action == "url":
        if not parsed.target or not parsed.target.startswith(("https://", "http://")):
            parser.error("url benötigt eine vollständige http(s)-Adresse")
        webbrowser.open(parsed.target)
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
