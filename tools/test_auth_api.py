#!/usr/bin/env python3

import importlib.util
import io
import json
import os
import tempfile
from pathlib import Path


def load_server():
    configured_path = os.environ.get("PI_CONTROL_SERVER_PATH")
    server_path = (
        Path(configured_path)
        if configured_path
        else Path(__file__).resolve().parents[1]
        / "deploy"
        / "pi-server"
        / "server.py"
    )
    spec = importlib.util.spec_from_file_location("pi_control_server", server_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def auth_header(token):
    return {"Authorization": f"Bearer {token}"}


def main():
    server = load_server()

    with tempfile.TemporaryDirectory(prefix="pi-control-auth-test-") as temp:
        temp_path = Path(temp)
        server.AUTH_DB_FILE = temp_path / "auth.db"
        server.INITIAL_ADMIN_FILE = temp_path / "initial_admin.json"
        server.FILE_ROOT = temp_path / "files"
        server.FILE_ROOT.mkdir()
        server.os.path.ismount = lambda path: True
        server.initialize_auth_database()

        credentials = json.loads(
            server.INITIAL_ADMIN_FILE.read_text(encoding="utf-8")
        )
        client = server.app.test_client()

        login = client.post("/api/auth/login", json=credentials)
        assert login.status_code == 200, login.data
        admin_login = login.get_json()
        assert admin_login["user"]["must_change_password"] is True
        admin_token = admin_login["token"]

        blocked = client.get("/api/info", headers=auth_header(admin_token))
        assert blocked.status_code == 428

        changed = client.post(
            "/api/auth/password",
            headers=auth_header(admin_token),
            json={
                "current_password": credentials["password"],
                "new_password": "Auth-Test-Admin-2026!",
            },
        )
        assert changed.status_code == 200, changed.data

        remembered_login = client.post(
            "/api/auth/login",
            base_url="https://localhost",
            json={
                "username": credentials["username"],
                "password": "Auth-Test-Admin-2026!",
                "remember_me": True,
                "cookie_only": True,
            },
        )
        assert remembered_login.status_code == 200, remembered_login.data
        assert remembered_login.get_json()["token"] is None
        cookie_header = remembered_login.headers.get("Set-Cookie", "")
        assert "pi_control_session=" in cookie_header
        assert "Max-Age=2592000" in cookie_header
        assert "HttpOnly" in cookie_header
        assert "Secure" in cookie_header
        assert "SameSite=Lax" in cookie_header
        assert "Path=/api" in cookie_header

        restored = client.get(
            "/api/auth/me",
            base_url="https://localhost",
        )
        assert restored.status_code == 200, restored.data
        assert restored.get_json()["user"]["username"] == credentials[
            "username"
        ]

        logged_out = client.post(
            "/api/auth/logout",
            base_url="https://localhost",
        )
        assert logged_out.status_code == 200, logged_out.data
        assert "Max-Age=0" in logged_out.headers.get("Set-Cookie", "")
        assert client.get(
            "/api/auth/me",
            base_url="https://localhost",
        ).status_code == 401

        server.execute_terminal_command = lambda command, cwd: {
            "output": f"ran: {command}",
            "exit_code": 0,
            "cwd": cwd,
            "timed_out": False,
            "truncated": False,
        }
        terminal = client.post(
            "/api/terminal/execute",
            headers=auth_header(admin_token),
            json={"command": "uptime", "cwd": "/home/pi-terminal"},
        )
        assert terminal.status_code == 200, terminal.data
        assert terminal.get_json()["output"] == "ran: uptime"

        create_user = client.post(
            "/api/admin/users",
            headers=auth_header(admin_token),
            json={
                "username": "viewer",
                "display_name": "Viewer",
                "password": "Auth-Test-Viewer-2026!",
                "is_admin": False,
                "permissions": [
                    "dashboard_view",
                    "files_view",
                    "files_upload",
                    "files_manage",
                    "terminal_access",
                ],
                "storage_path": "users/viewer",
                "storage_quota_bytes": 4,
            },
        )
        assert create_user.status_code == 201, create_user.data
        assert "terminal_access" not in create_user.get_json()["user"][
            "permissions"
        ]
        assert create_user.get_json()["user"]["storage_path"] == "users/viewer"
        assert create_user.get_json()["user"]["storage_quota_bytes"] == 4

        viewer_login = client.post(
            "/api/auth/login",
            json={
                "username": "viewer",
                "password": "Auth-Test-Viewer-2026!",
            },
        ).get_json()
        viewer_token = viewer_login["token"]

        viewer_changed = client.post(
            "/api/auth/password",
            headers=auth_header(viewer_token),
            json={
                "current_password": "Auth-Test-Viewer-2026!",
                "new_password": "Auth-Test-Viewer-Neu-2026!",
            },
        )
        assert viewer_changed.status_code == 200, viewer_changed.data

        assert client.get(
            "/api/info",
            headers=auth_header(viewer_token),
        ).status_code == 200
        server.FILE_ROOT.joinpath("outside.txt").write_text(
            "not visible",
            encoding="utf-8",
        )
        viewer_files = client.get(
            "/api/files",
            headers=auth_header(viewer_token),
        )
        assert viewer_files.status_code == 200, viewer_files.data
        assert viewer_files.get_json()["storage_path"] == "users/viewer"
        assert viewer_files.get_json()["storage_quota_bytes"] == 4
        assert viewer_files.get_json()["entries"] == []

        small_upload = client.post(
            "/api/files/upload",
            headers=auth_header(viewer_token),
            data={
                "path": "",
                "file": (io.BytesIO(b"abc"), "small.txt"),
            },
            content_type="multipart/form-data",
        )
        assert small_upload.status_code == 200, small_upload.data

        destination_folder = client.post(
            "/api/files/folder",
            headers=auth_header(viewer_token),
            json={"path": "", "name": "Dokumente"},
        )
        assert destination_folder.status_code == 200, destination_folder.data

        moved = client.post(
            "/api/files/move",
            headers=auth_header(viewer_token),
            json={"path": "small.txt", "destination": "Dokumente"},
        )
        assert moved.status_code == 200, moved.data
        assert server.FILE_ROOT.joinpath(
            "users/viewer/Dokumente/small.txt"
        ).read_bytes() == b"abc"

        nested_folder = client.post(
            "/api/files/folder",
            headers=auth_header(viewer_token),
            json={"path": "Dokumente", "name": "Unterordner"},
        )
        assert nested_folder.status_code == 200, nested_folder.data

        move_into_itself = client.post(
            "/api/files/move",
            headers=auth_header(viewer_token),
            json={"path": "Dokumente", "destination": "Dokumente/Unterordner"},
        )
        assert move_into_itself.status_code == 409, move_into_itself.data

        quota_blocked = client.post(
            "/api/files/upload",
            headers=auth_header(viewer_token),
            data={
                "path": "",
                "file": (io.BytesIO(b"de"), "too-much.txt"),
            },
            content_type="multipart/form-data",
        )
        assert quota_blocked.status_code == 413, quota_blocked.data
        assert not server.FILE_ROOT.joinpath(
            "users/viewer/too-much.txt"
        ).exists()

        traversal = client.get(
            "/api/files?path=../",
            headers=auth_header(viewer_token),
        )
        assert traversal.status_code == 409, traversal.data
        assert client.get(
            "/api/admin/users",
            headers=auth_header(viewer_token),
        ).status_code == 403
        assert client.post(
            "/api/reboot",
            headers=auth_header(viewer_token),
        ).status_code == 403
        assert client.post(
            "/api/terminal/execute",
            headers=auth_header(viewer_token),
            json={"command": "id"},
        ).status_code == 403

    print("AUTH_API_OK")


if __name__ == "__main__":
    main()
