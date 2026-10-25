"""Bounded multi-step task execution for the Pi-Control PC Agent.

Only explicitly enumerated read-only actions are executable by an unattended plan.
The runner never interprets natural-language text as a command and never performs
file writes, deletes, app launches, or arbitrary command execution.
"""
from __future__ import annotations

from typing import Any, Callable

MAX_STEPS = 8
ALLOWED_ACTIONS = {"status", "git_status", "git_diff", "read_file", "list_files", "tests"}
STEP_FIELDS = {
    "status": {"action"},
    "git_status": {"action"},
    "git_diff": {"action", "path"},
    "read_file": {"action", "path"},
    "list_files": {"action", "path"},
    "tests": {"action"},
}


class PlanValidationError(ValueError):
    """Raised when a task plan is malformed or asks for an unsafe action."""


def validate_git_diff_path(path: Any) -> str:
    """Accept one concrete, repository-relative path for git diff."""
    if not isinstance(path, str) or not path or len(path) > 1000:
        raise PlanValidationError("git_diff benötigt genau einen gültigen Dateipfad.")
    if path != path.strip() or "\x00" in path or "\\" in path:
        raise PlanValidationError("Ungültiger Dateipfad für git_diff.")
    if path.startswith("/") or ":" in path:
        raise PlanValidationError("git_diff erlaubt nur relative Dateipfade.")
    parts = path.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        raise PlanValidationError("Ungültiger Pfadbestandteil für git_diff.")
    if any(char in path for char in "*?[]"):
        raise PlanValidationError("git_diff erlaubt keine Muster oder Wildcards.")
    if any(part == ".git" for part in parts):
        raise PlanValidationError("git_diff darf nicht auf .git zugreifen.")
    protected = {
        "history.json",
        "server/test_auth_api.py",
        "pc_agent_write_probe.txt",
    }
    if path in protected:
        raise PlanValidationError("Dieser Dateipfad ist für git_diff gesperrt.")
    return path


def validate_plan(title: Any, goal: Any, steps: Any) -> list[dict[str, str]]:
    if not isinstance(title, str) or not title.strip() or len(title) > 200:
        raise PlanValidationError("title muss nichtleerer Text mit höchstens 200 Zeichen sein.")
    if not isinstance(goal, str) or not goal.strip() or len(goal) > 4000:
        raise PlanValidationError("goal muss nichtleerer Text mit höchstens 4000 Zeichen sein.")
    if not isinstance(steps, list) or not 1 <= len(steps) <= MAX_STEPS:
        raise PlanValidationError(f"steps muss eine Liste mit 1 bis {MAX_STEPS} Schritten sein.")

    normalized = []
    for index, step in enumerate(steps, start=1):
        if not isinstance(step, dict):
            raise PlanValidationError(f"Schritt {index} muss ein Objekt sein.")
        action = step.get("action")
        if action not in ALLOWED_ACTIONS:
            raise PlanValidationError(
                f"Aktion in Schritt {index} ist nicht für automatische Ausführung freigegeben."
            )
        if set(step) - STEP_FIELDS[action]:
            unknown = sorted(set(step) - STEP_FIELDS[action])
            raise PlanValidationError(f"Schritt {index} enthält unbekannte Felder: {chr(44).join(unknown)}.")
        item = {"action": action}
        if action in {"read_file", "list_files"}:
            path = step.get("path", "." if action == "list_files" else "")
            if not isinstance(path, str) or not path.strip() or len(path) > 1000:
                raise PlanValidationError(f"Schritt {index} benötigt einen gültigen Pfad.")
            item["path"] = path
        if action == "git_diff":
            item["path"] = validate_git_diff_path(step.get("path", ""))
        normalized.append(item)
    return normalized


def run_plan(
    memory: Any,
    title: str,
    goal: str,
    steps: Any,
    execute: Callable[[dict[str, str]], dict[str, Any]],
) -> dict[str, Any]:
    """Validate first, then run safe steps sequentially and journal every result."""
    plan = validate_plan(title, goal, steps)
    task = memory.start_task(title.strip(), goal.strip())
    results = []
    for index, step in enumerate(plan, start=1):
        label = f"{index}/{len(plan)} {step['action']}"
        try:
            result = execute(step)
            if not isinstance(result, dict):
                raise TypeError("Aktion lieferte kein Ergebnisobjekt.")
            succeeded = result.get("ok", True) is True
            status = "in_progress" if succeeded and index < len(plan) else (
                "completed" if succeeded else "failed"
            )
            message = "Schritt erfolgreich." if succeeded else "Schritt fehlgeschlagen."
            memory.record_step(
                task["id"], label, message, details={"action": step["action"], "result": result},
                status=status,
                summary=("Alle sicheren Schritte abgeschlossen." if status == "completed" else None),
                next_step=(None if status in {"completed", "failed"} else f"Schritt {index + 1}"),
            )
            results.append({"step": label, **result})
            if not succeeded:
                return {"ok": False, "task_id": task["id"], "status": "failed", "results": results}
        except Exception as exc:
            message = str(exc)[:500] or exc.__class__.__name__
            memory.record_step(
                task["id"], label, "Schritt mit Fehler abgebrochen.",
                details={"action": step["action"], "error": message},
                status="failed", summary=message,
            )
            results.append({"step": label, "ok": False, "error": message})
            return {"ok": False, "task_id": task["id"], "status": "failed", "results": results}
    return {"ok": True, "task_id": task["id"], "status": "completed", "results": results}
