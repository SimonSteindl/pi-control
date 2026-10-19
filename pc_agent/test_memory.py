"""Unit tests for persistent PC Agent task memory (standard-library unittest)."""
import tempfile
import unittest
from pathlib import Path

from pc_agent.memory import AgentMemory


class AgentMemoryTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.memory = AgentMemory(Path(self.temp_dir.name) / "memory.sqlite3")

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_task_survives_reopening_store(self):
        task = self.memory.start_task("Improve tests", "Inspect and run tests")
        self.memory.record_step(
            task["id"],
            "run tests",
            "Test command returned exit code 1",
            details={"exit_code": 1},
            status="paused",
            summary="Tests found a failure",
            next_step="Inspect the failing assertion",
        )

        reopened = AgentMemory(Path(self.temp_dir.name) / "memory.sqlite3")
        context = reopened.resume_context()
        self.assertTrue(context["has_active_task"])
        self.assertEqual(context["task"]["id"], task["id"])
        self.assertEqual(context["task"]["next_step"], "Inspect the failing assertion")
        self.assertEqual(context["events"][-1]["details"]["exit_code"], 1)

    def test_completed_task_is_not_active(self):
        task = self.memory.start_task("Small change", "Make one safe change")
        self.memory.record_step(
            task["id"], "verify", "Checks passed", status="completed"
        )
        self.assertIsNone(self.memory.current_task())

    def test_unknown_task_raises(self):
        with self.assertRaises(KeyError):
            self.memory.record_step("missing", "step", "message")

    def test_invalid_status_raises(self):
        task = self.memory.start_task("Task", "Goal")
        with self.assertRaises(ValueError):
            self.memory.record_step(task["id"], "step", "message", status="unknown")


if __name__ == "__main__":
    unittest.main()
