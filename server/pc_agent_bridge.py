"""Authenticated, read-only queue for the outbound PC agent bridge.

Set PI_CONTROL_PC_AGENT_TOKEN to the same long random secret on the Pi server
and the PC. Never expose the local PC-agent API itself to the internet.
"""
from collections import deque
import hmac
import os
import secrets
import threading
import time
from flask import jsonify, request

_lock = threading.Lock()
_pending = deque(maxlen=100)
_results = deque(maxlen=100)


def register_pc_agent_bridge(app):
    def authorized():
        expected = os.environ.get("PI_CONTROL_PC_AGENT_TOKEN", "")
        supplied = request.headers.get("Authorization", "")
        supplied = supplied[7:].strip() if supplied.startswith("Bearer ") else ""
        return bool(expected) and hmac.compare_digest(supplied, expected)

    @app.post("/api/pc-agent/tasks")
    def pc_agent_enqueue():
        if not authorized():
            return jsonify({"ok": False, "error": "unauthorized"}), 401
        data = request.get_json(silent=True) or {}
        action = data.get("action")
        path = data.get("path", "")
        if action not in ("list_files", "read_file"):
            return jsonify({"ok": False, "error": "unsupported action"}), 400
        if not isinstance(path, str) or len(path) > 2048 or "\x00" in path:
            return jsonify({"ok": False, "error": "invalid path"}), 400
        task = {"id": secrets.token_urlsafe(18), "action": action,
                "path": path, "created_at": int(time.time())}
        with _lock:
            if len(_pending) >= 100:
                return jsonify({"ok": False, "error": "queue full"}), 429
            _pending.append(task)
        return jsonify({"ok": True, "task_id": task["id"]}), 202

    @app.get("/api/pc-agent/next")
    def pc_agent_next():
        if not authorized():
            return jsonify({"ok": False, "error": "unauthorized"}), 401
        with _lock:
            task = _pending.popleft() if _pending else None
        return jsonify({"ok": True, "task": task})

    @app.post("/api/pc-agent/results")
    def pc_agent_result():
        if not authorized():
            return jsonify({"ok": False, "error": "unauthorized"}), 401
        data = request.get_json(silent=True) or {}
        task_id = data.get("task_id")
        if not isinstance(task_id, str) or len(task_id) > 128:
            return jsonify({"ok": False, "error": "invalid task_id"}), 400
        result = {"task_id": task_id, "ok": bool(data.get("ok")),
                  "result": data.get("result"), "received_at": int(time.time())}
        with _lock:
            _results.append(result)
        return jsonify({"ok": True}), 202

    @app.get("/api/pc-agent/results")
    def pc_agent_results():
        if not authorized():
            return jsonify({"ok": False, "error": "unauthorized"}), 401
        with _lock:
            results = list(_results)
        return jsonify({"ok": True, "results": results})
