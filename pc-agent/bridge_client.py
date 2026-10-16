#!/usr/bin/env python3
"""Outbound polling bridge for Pi-Control PC Agent (read-only actions only)."""
import json
import os
import time
import urllib.error
import urllib.request

PI_URL = os.environ.get("PI_CONTROL_SERVER_URL", "").rstrip("/")
BRIDGE_TOKEN = os.environ.get("PI_CONTROL_PC_AGENT_TOKEN", "")
LOCAL_AGENT_URL = os.environ.get("PI_CONTROL_LOCAL_AGENT_URL", "http://127.0.0.1:8765")
POLL_SECONDS = max(2, int(os.environ.get("PI_CONTROL_BRIDGE_POLL_SECONDS", "5")))


def request_json(url, method="GET", payload=None, token=None, timeout=15):
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    headers = {"Accept": "application/json"}
    if body is not None:
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        raw = response.read(2 * 1024 * 1024)
    return json.loads(raw.decode("utf-8"))


def local_request(path, token):
    return request_json(LOCAL_AGENT_URL + path, token=token, timeout=10)


def execute_task(task, local_token):
    action, path = task.get("action"), task.get("path", "")
    from urllib.parse import quote
    if action == "list_files":
        return local_request("/v1/files?path=" + quote(path, safe=""), local_token)
    if action == "read_file":
        return local_request("/v1/file?path=" + quote(path, safe=""), local_token)
    raise ValueError("Unsupported task action")


def main():
    if not PI_URL.startswith("https://") or not BRIDGE_TOKEN:
        raise SystemExit("Set PI_CONTROL_SERVER_URL (HTTPS) and PI_CONTROL_PC_AGENT_TOKEN.")
    token_path = os.path.expanduser("~/.pi-control-agent/token")
    try:
        with open(token_path, encoding="utf-8") as handle:
            local_token = handle.read().strip()
    except OSError as exc:
        raise SystemExit(f"Cannot read local agent token at {token_path}: {exc}")
    print("Pi-Control outbound bridge running. Allowed actions: list_files, read_file.")
    while True:
        try:
            response = request_json(PI_URL + "/api/pc-agent/next", token=BRIDGE_TOKEN, timeout=20)
            task = response.get("task")
            if task:
                try:
                    result = execute_task(task, local_token)
                    report = {"task_id": task["id"], "ok": True, "result": result}
                except Exception as exc:
                    report = {"task_id": task.get("id", ""), "ok": False,
                              "result": {"error": str(exc)[:500]}}
                request_json(PI_URL + "/api/pc-agent/results", method="POST",
                             payload=report, token=BRIDGE_TOKEN, timeout=15)
        except urllib.error.HTTPError as exc:
            if exc.code == 401:
                raise SystemExit("Bridge token rejected by Pi-Control server.")
            print(f"Bridge HTTP error: {exc.code}")
        except (urllib.error.URLError, TimeoutError, ValueError, OSError) as exc:
            print(f"Bridge connection error: {exc}")
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
