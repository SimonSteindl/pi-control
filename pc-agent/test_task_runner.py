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

    def test_accepts_python_syntax_as_pathless_read_only_action(self):
        plan = validate_plan("Syntax", "Check Python syntax", [
            {"action": "python_syntax"},
        ])
        self.assertEqual(plan, [{"action": "python_syntax"}])
        with self.assertRaises(PlanValidationError):
            validate_plan("Syntax", "Check Python syntax", [
                {"action": "python_syntax", "path": "server"},
            ])

    def test_accepts_focused_test_file_and_text_replacement_steps(self):
        plan = validate_plan("Repair", "Fix and test a project change", [
            {"action": "replace_text", "path": "server/server.py", "old_text": "before", "new_text": "after"},
            {"action": "test_file", "path": "server/test_ai_memory.py"},
        ])
        self.assertEqual(plan[0]["action"], "replace_text")
        self.assertEqual(plan[1], {"action": "test_file", "path": "server/test_ai_memory.py"})
        for step in (
            {"action": "replace_text", "path": "server.py", "old_text": "", "new_text": "x"},
            {"action": "replace_text", "path": "server.py", "old_text": "x", "new_text": "x" * 20001},
            {"action": "test_file", "path": "server/test_ai_memory.py", "command": ["python"]},
        ):
            with self.subTest(step=step), self.assertRaises(PlanValidationError):
                validate_plan("Repair", "Fix and test", [step])

    def test_accepts_one_scoped_flutter_test_and_rejects_extra_fields(self):
        self.assertEqual(
            validate_plan("Flutter", "Test one app feature", [
                {"action": "flutter_test", "path": "app/test/widget_test.dart"},
            ]),
            [{"action": "flutter_test", "path": "app/test/widget_test.dart"}],
        )
        with self.assertRaises(PlanValidationError):
            validate_plan("Flutter", "Test one app feature", [
                {"action": "flutter_test", "path": "app/test/widget_test.dart", "command": ["sh"]},
            ])

    def test_accepts_bounded_write_file_and_rejects_malformed_writes(self):
        plan = validate_plan("Edit", "Update a project file", [
            {"action": "write_file", "path": "docs/note.md", "content": "hello"}
        ])
        self.assertEqual(plan[0], {"action": "write_file", "path": "docs/note.md", "content": "hello"})
        for step in (
            {"action": "write_file", "path": "note.md"},
            {"action": "write_file", "path": "note.md", "content": "x" * 20001},
            {"action": "write_file", "path": "note.md", "content": "ok", "command": "echo bad"},
        ):
            with self.subTest(step=step), self.assertRaises(PlanValidationError):
                validate_plan("Edit", "Update a project file", [step])

    def test_rejects_arbitrary_commands_and_deletions(self):
        for action in ("run_command", "delete_file", "open"):
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
