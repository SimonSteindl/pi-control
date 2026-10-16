#!/usr/bin/env python3
"""Regression tests for the authenticated read-only PC-Agent bridge."""
import os
import sys
import unittest
from functools import wraps
from pathlib import Path
from unittest.mock import patch

from flask import Flask, jsonify, request

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pc_agent_bridge


def test_user_required(function):
    @wraps(function)
    def wrapped(*args, **kwargs):
        if request.headers.get("X-Test-User") != "yes":
            return jsonify({"ok": False, "error": "login required"}), 401
        return function(*args, **kwargs)
    return wrapped


class PcAgentBridgeTests(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {"PI_CONTROL_PC_AGENT_TOKEN": "test-bridge-token"})
        self.env.start()
        with pc_agent_bridge._lock:
            pc_agent_bridge._pending.clear()
            pc_agent_bridge._known_tasks.clear()
            pc_agent_bridge._completed.clear()
            pc_agent_bridge._results.clear()
        self.app = Flask(__name__)
        self.app.testing = True
        pc_agent_bridge.register_pc_agent_bridge(self.app, enqueue_auth=lambda: test_user_required)
        self.client = self.app.test_client()

    def tearDown(self):
        self.env.stop()

    def test_task_creation_requires_pi_control_login(self):
        response = self.client.post(
            "/api/pc-agent/tasks",
            json={"action": "list_files", "path": "pi-control"},
        )
        self.assertEqual(response.status_code, 401)

    def test_task_creation_is_session_authenticated_not_worker_token_authenticated(self):
        response = self.client.post(
            "/api/pc-agent/tasks",
            json={"action": "list_files", "path": "pi-control"},
            headers={"X-Test-User": "yes"},
        )
        self.assertEqual(response.status_code, 202)
        self.assertTrue(response.get_json()["task_id"])

    def test_rejects_paths_outside_project(self):
        response = self.client.post(
            "/api/pc-agent/tasks",
            json={"action": "read_file", "path": "../.ssh/id_rsa"},
            headers={"X-Test-User": "yes"},
        )
        self.assertEqual(response.status_code, 400)

    def test_worker_token_required_and_result_correlated(self):
        task_id = pc_agent_bridge.enqueue_pc_agent_task("list_files", "pi-control")
        denied = self.client.get("/api/pc-agent/next")
        self.assertEqual(denied.status_code, 401)

        task_response = self.client.get(
            "/api/pc-agent/next",
            headers={"Authorization": "Bearer test-bridge-token"},
        )
        self.assertEqual(task_response.status_code, 200)
        self.assertEqual(task_response.get_json()["task"]["id"], task_id)

        result_response = self.client.post(
            "/api/pc-agent/results",
            json={"task_id": task_id, "ok": True, "result": {"entries": []}},
            headers={"Authorization": "Bearer test-bridge-token"},
        )
        self.assertEqual(result_response.status_code, 202)
        result = pc_agent_bridge.wait_for_pc_agent_result(task_id, timeout=0)
        self.assertIsNotNone(result)
        self.assertTrue(result["ok"])
        self.assertEqual(result["result"], {"entries": []})

    def test_rejects_unknown_worker_result(self):
        response = self.client.post(
            "/api/pc-agent/results",
            json={"task_id": "not-a-real-task", "ok": True, "result": {}},
            headers={"Authorization": "Bearer test-bridge-token"},
        )
        self.assertEqual(response.status_code, 404)


if __name__ == "__main__":
    unittest.main()
