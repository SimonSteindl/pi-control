"""Persistent task memory for the Pi-Control PC Agent.

This module stores resumable task state in SQLite. It deliberately does not
execute commands or edit project files; the agent server must call this store
when tasks and steps start, finish, or fail.
"""
from __future__ import annotations

import json
import os
import sqlite3
import time
import uuid
from pathlib import Path
from typing import Any


class AgentMemory:
    """Small, thread-safe-by-connection SQLite journal for agent tasks."""

    def __init__(self, db_path: str | os.PathLike[str] | None = None) -> None:
        default_root = Path.home() / ".local" / "share" / "pi-control"
        self.db_path = Path(
            db_path
            or os.environ.get("PI_CONTROL_AGENT_MEMORY_DB")
            or (default_root / "agent-memory.sqlite3")
        ).expanduser()
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._initialize()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(str(self.db_path), timeout=10)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA busy_timeout = 10000")
        connection.execute("PRAGMA journal_mode = WAL")
        return connection

    def _initialize(self) -> None:
        with self._connect() as db:
            db.execute(
                """
                CREATE TABLE IF NOT EXISTS tasks (
                    id TEXT PRIMARY KEY,
                    title TEXT NOT NULL,
                    goal TEXT NOT NULL,
                    status TEXT NOT NULL,
                    current_step TEXT NOT NULL DEFAULT '',
                    summary TEXT NOT NULL DEFAULT '',
                    next_step TEXT NOT NULL DEFAULT '',
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                )
                """
            )
            db.execute(
                """
                CREATE TABLE IF NOT EXISTS events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    task_id TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    message TEXT NOT NULL,
                    details_json TEXT NOT NULL DEFAULT '{}',
                    created_at REAL NOT NULL,
                    FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE
                )
                """
            )
            db.execute(
                "CREATE INDEX IF NOT EXISTS idx_agent_events_task "
                "ON events(task_id, id)"
            )

    @staticmethod
    def _task(row: sqlite3.Row | None) -> dict[str, Any] | None:
        return dict(row) if row is not None else None

    def start_task(self, title: str, goal: str) -> dict[str, Any]:
        now = time.time()
        task_id = str(uuid.uuid4())
        with self._connect() as db:
            db.execute(
                """INSERT INTO tasks
                   (id, title, goal, status, created_at, updated_at)
                   VALUES (?, ?, ?, 'in_progress', ?, ?)""",
                (task_id, title.strip(), goal.strip(), now, now),
            )
            self._event(db, task_id, "task_started", "Task started", {})
            return self._task(db.execute(
                "SELECT * FROM tasks WHERE id = ?", (task_id,)
            ).fetchone()) or {}

    def record_step(
        self,
        task_id: str,
        step: str,
        message: str,
        *,
        details: dict[str, Any] | None = None,
        status: str = "in_progress",
        summary: str | None = None,
        next_step: str | None = None,
    ) -> dict[str, Any]:
        allowed = {"in_progress", "paused", "completed", "failed", "cancelled"}
        if status not in allowed:
            raise ValueError(f"Unsupported task status: {status}")
        now = time.time()
        with self._connect() as db:
            existing = db.execute(
                "SELECT id FROM tasks WHERE id = ?", (task_id,)
            ).fetchone()
            if existing is None:
                raise KeyError(f"Unknown task: {task_id}")
            db.execute(
                """UPDATE tasks SET status = ?, current_step = ?,
                   summary = COALESCE(?, summary),
                   next_step = COALESCE(?, next_step), updated_at = ?
                   WHERE id = ?""",
                (status, step, summary, next_step, now, task_id),
            )
            self._event(db, task_id, "step", message, details or {})
            return self._task(db.execute(
                "SELECT * FROM tasks WHERE id = ?", (task_id,)
            ).fetchone()) or {}

    def _event(
        self,
        db: sqlite3.Connection,
        task_id: str,
        kind: str,
        message: str,
        details: dict[str, Any],
    ) -> None:
        db.execute(
            """INSERT INTO events
               (task_id, kind, message, details_json, created_at)
               VALUES (?, ?, ?, ?, ?)""",
            (task_id, kind, message, json.dumps(details, ensure_ascii=False), time.time()),
        )

    def current_task(self) -> dict[str, Any] | None:
        with self._connect() as db:
            row = db.execute(
                """SELECT * FROM tasks WHERE status IN ('in_progress', 'paused')
                   ORDER BY updated_at DESC LIMIT 1"""
            ).fetchone()
            return self._task(row)

    def get_task(self, task_id: str) -> dict[str, Any] | None:
        with self._connect() as db:
            return self._task(db.execute(
                "SELECT * FROM tasks WHERE id = ?", (task_id,)
            ).fetchone())

    def task_events(self, task_id: str, limit: int = 100) -> list[dict[str, Any]]:
        limit = max(1, min(int(limit), 500))
        with self._connect() as db:
            rows = db.execute(
                """SELECT kind, message, details_json, created_at
                   FROM events WHERE task_id = ? ORDER BY id DESC LIMIT ?""",
                (task_id, limit),
            ).fetchall()
        events = []
        for row in reversed(rows):
            item = dict(row)
            item["details"] = json.loads(item.pop("details_json"))
            events.append(item)
        return events

    def recent_tasks(self, limit: int = 20) -> list[dict[str, Any]]:
        limit = max(1, min(int(limit), 100))
        with self._connect() as db:
            rows = db.execute(
                "SELECT * FROM tasks ORDER BY updated_at DESC LIMIT ?", (limit,)
            ).fetchall()
            return [dict(row) for row in rows]

    def resume_context(self) -> dict[str, Any]:
        """Return the active task and its latest journal entries for restart recovery."""
        task = self.current_task()
        if task is None:
            return {"has_active_task": False, "task": None, "events": []}
        return {
            "has_active_task": True,
            "task": task,
            "events": self.task_events(task["id"], limit=30),
        }
