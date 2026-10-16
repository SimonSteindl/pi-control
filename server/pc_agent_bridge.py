"""Authenticated, read-only outbound queue for the Pi-Control PC agent.

Browser/chat task creation uses Pi-Control's normal session authentication.
Only the outbound PC worker uses PI_CONTROL_PC_AGENT_TOKEN for polling/results.
Tasks are restricted to the user's pi-control project folder and read-only actions.
"""
from collections import deque
import hmac
import os
import secrets
import threading
import time

from flask import jsonify, request

_MAX_PENDING = 100
_MAX_RESULTS = 100
_lock = threading.Condition()
_pending = deque()
_known_tasks = {}
_completed = {}
_results = deque(maxlen=_MAX_RESULTS)


def _validate_task(action, path):
    if action not in ("list_files", "read_file"):
        raise ValueError("Unsupported action")
    if not isinstance(path, str) or not path or len(path) > 2048 or "\x00" in path:
        raise ValueError("Invalid path")
    # The bridge may only inspect the checked-out project, never arbitrary home files.
    if path.startswith(("/", "\\")) or "\\" in path or ":" in path:
        raise ValueError("Only project-relative paths are allowed")
    parts = path.split("/")
    if parts[0] != "pi-control" or any(part in ("", ".", "..") for part in parts):
        if path != "pi-control":
            raise ValueError("Path must stay inside the pi-control project")
    if any(part.lower() in {".git", ".ssh", ".gnupg", ".pki", ".password-store"} for part in parts):
        raise ValueError("Private or internal folders are not available through the bridge")
    return path


def enqueue_pc_agent_task(action, path):
    """Queue a validated task from an already authenticated Pi-Control request."""
    path = _validate_task(action, path)
    task = {
        "id": secrets.token_urlsafe(18),
        "action": action,
        "path": path,
        "created_at": int(time.time()),
    }
    with _lock:
        if len(_pending) >= _MAX_PENDING:
            raise RuntimeError("PC-Agent task queue is full")
        _pending.append(task)
        _known_tasks[task["id"]] = task["created_at"]
        # Bound stale task metadata if a worker disappeared.
        if len(_known_tasks) > _MAX_PENDING * 3:
            active_ids = {item["id"] for item in _pending}
            active_ids.update(_completed)
            for old_id in list(_known_tasks):
                if old_id not in active_ids:
                    _known_tasks.pop(old_id, None)
                    if len(_known_tasks) <= _MAX_PENDING * 2:
                        break
        _lock.notify_all()
    return task["id"]


def wait_for_pc_agent_result(task_id, timeout=30):
    """Wait briefly for a worker result; return None on timeout."""
    deadline = time.monotonic() + max(0, timeout)
    with _lock:
        while task_id not in _completed:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return None
            _lock.wait(min(remaining, 1.0))
        return _completed.pop(task_id)


def register_pc_agent_bridge(app, enqueue_auth=None):
    def authorized_worker():
        expected = os.environ.get("PI_CONTROL_PC_AGENT_TOKEN", "")
        supplied = request.headers.get("Authorization", "")
        supplied = supplied[7:].strip() if supplied.startswith("Bearer ") else ""
        return bool(expected) and hmac.compare_digest(supplied, expected)

    def pc_agent_enqueue():
        data = request.get_json(silent=True) or {}
        try:
            task_id = enqueue_pc_agent_task(data.get("action"), data.get("path", ""))
        except RuntimeError as exc:
            return jsonify({"ok": False, "error": str(exc)}), 429
        except ValueError as exc:
            return jsonify({"ok": False, "error": str(exc)}), 400
        return jsonify({"ok": True, "task_id": task_id}), 202

    # This endpoint is for the authenticated Pi-Control UI/chat, not the worker token.
    enqueue_view = enqueue_auth(pc_agent_enqueue) if enqueue_auth else pc_agent_enqueue
    app.add_url_rule(
        "/api/pc-agent/tasks",
        endpoint="pc_agent_enqueue",
        view_func=enqueue_view,
        methods=["POST"],
    )

    @app.get("/api/pc-agent/next")
    def pc_agent_next():
        if not authorized_worker():
            return jsonify({"ok": False, "error": "unauthorized"}), 401
        with _lock:
            task = _pending.popleft() if _pending else None
        return jsonify({"ok": True, "task": task})

    @app.post("/api/pc-agent/results")
    def pc_agent_result():
        if not authorized_worker():
            return jsonify({"ok": False, "error": "unauthorized"}), 401
        if request.content_length is not None and request.content_length > 2 * 1024 * 1024:
            return jsonify({"ok": False, "error": "result too large"}), 413
        data = request.get_json(silent=True) or {}
        task_id = data.get("task_id")
        if not isinstance(task_id, str) or len(task_id) > 128:
            return jsonify({"ok": False, "error": "invalid task_id"}), 400
        with _lock:
            if task_id not in _known_tasks:
                return jsonify({"ok": False, "error": "unknown task"}), 404
            result = {
                "task_id": task_id,
                "ok": bool(data.get("ok")),
                "result": data.get("result"),
                "received_at": int(time.time()),
            }
            _completed[task_id] = result
            _results.append(result)
            _known_tasks.pop(task_id, None)
            _lock.notify_all()
        return jsonify({"ok": True}), 202

    @app.get("/api/pc-agent/results")
    def pc_agent_results():
        if not authorized_worker():
            return jsonify({"ok": False, "error": "unauthorized"}), 401
        with _lock:
            results = list(_results)
        return jsonify({"ok": True, "results": results})
