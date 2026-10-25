import unittest
from pathlib import Path
import sys
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from pc_agent.task_runner import PlanValidationError, run_plan, validate_plan


class TaskRunnerTests(unittest.TestCase):
    def test_git_diff_requires_one_safe_path(self):
        plan = validate_plan("Diff", "Inspect one file", [
            {"action": "git_diff", "path": "server/README.md"}
        ])
        self.assertEqual(
            plan[0], {"action": "git_diff", "path": "server/README.md"}
        )

    def test_git_diff_rejects_missing_unsafe_and_protected_paths(self):
        invalid_paths = (
            "",
            "../outside.txt",
            "history.json",
            "server/test_auth_api.py",
            "pc_agent_write_probe.txt",
            ":(glob)**",
            "/etc/passwd",
            "server//README.md",
        )
        for path in invalid_paths:
            with self.subTest(path=path), self.assertRaises(PlanValidationError):
                validate_plan("Diff", "Inspect safely", [
                    {"action": "git_diff", "path": path}
                ])

    def test_validates_and_normalizes_safe_plan(self):
        plan = validate_plan("Check", "Check repository", [
            {"action": "git_status"}, {"action": "read_file", "path": "README.md"},
            {"action": "list_files"},
        ])
        self.assertEqual(plan[1], {"action": "read_file", "path": "README.md"})
        self.assertEqual(plan[2], {"action": "list_files", "path": "."})

    def test_rejects_arbitrary_commands_and_mutations(self):
        for action in ("run_command", "write_file", "delete_file", "open"):
            with self.subTest(action=action), self.assertRaises(PlanValidationError):
                validate_plan("Unsafe", "Do something", [{"action": action}])

    def test_rejects_unknown_fields_and_too_many_steps(self):
        with self.assertRaises(PlanValidationError):
            validate_plan("Check", "Goal", [{"action": "git_status", "command": "rm -rf /"}])
        with self.assertRaises(PlanValidationError):
            validate_plan("Check", "Goal", [{"action": "status"}] * 9)

    def test_runs_steps_sequentially_and_completes_memory(self):
        memory = Mock()
        memory.start_task.return_value = {"id": "task-1"}
        calls = []
        def execute(step):
            calls.append(step["action"])
            return {"ok": True, "value": step["action"]}
        result = run_plan(memory, "Check", "Goal", [
            {"action": "status"}, {"action": "git_status"}
        ], execute)
        self.assertTrue(result["ok"])
        self.assertEqual(calls, ["status", "git_status"])
        self.assertEqual(memory.record_step.call_count, 2)
        self.assertEqual(memory.record_step.call_args.kwargs["status"], "completed")

    def test_stops_after_failure_and_marks_task_failed(self):
        memory = Mock()
        memory.start_task.return_value = {"id": "task-2"}
        calls = []
        def execute(step):
            calls.append(step["action"])
            return {"ok": False, "error": "failed"}
        result = run_plan(memory, "Check", "Goal", [
            {"action": "status"}, {"action": "git_status"}
        ], execute)
        self.assertFalse(result["ok"])
        self.assertEqual(calls, ["status"])
        self.assertEqual(memory.record_step.call_args.kwargs["status"], "failed")

    def test_invalid_plan_is_rejected_before_task_creation(self):
        memory = Mock()
        with self.assertRaises(PlanValidationError):
            run_plan(memory, "Unsafe", "Goal", [{"action": "run_command"}], lambda step: {})
        memory.start_task.assert_not_called()


if __name__ == "__main__":
    unittest.main()
