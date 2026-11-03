import io
import json
import unittest
from unittest.mock import patch

from server import server
from server.server import normalize_pc_agent_task_steps


class PcAgentTaskNormalizationTests(unittest.TestCase):
    def test_task_tool_schema_exposes_scoped_flutter_tests(self):
        schema = server.PC_AGENT_TASK_TOOL["function"]["parameters"]
        step = schema["properties"]["steps"]["items"]
        actions = step["properties"]["action"]["enum"]
        self.assertIn("flutter_test", actions)
        self.assertEqual(step["properties"]["path"]["type"], "string")

    def test_recovers_a_single_explicit_test_path_when_model_omits_it(self):
        arguments = {"steps": [{"action": "flutter_test"}]}
        messages = [{
            "role": "user",
            "content": "Führe bitte app/test/layout_system_test.dart aus.",
        }]
        self.assertEqual(
            server._fill_explicit_test_paths(arguments, messages),
            {"steps": [{"action": "flutter_test", "path": "app/test/layout_system_test.dart"}]},
        )
        ambiguous = [{
            "role": "user",
            "content": "Führe app/test/a_test.dart und app/test/b_test.dart aus.",
        }]
        self.assertEqual(
            server._fill_explicit_test_paths(arguments, ambiguous), arguments,
        )

    def test_only_successful_plan_steps_count_as_completed_actions(self):
        self.assertEqual(
            server._pc_plan_successful_actions({
                "actions": ["write_file", "test_file"],
                "task_result": {"results": [
                    {"step": "1/2 write_file", "ok": True},
                    {"step": "2/2 test_file", "ok": False},
                ]},
            }),
            ["write_file"],
        )

    def test_python_changes_get_a_syntax_check_and_merge_its_results(self):
        arguments = {
            "title": "Change Python file",
            "goal": "Change and check a project module",
            "steps": [{
                "action": "write_file", "path": "server/new_module.py",
                "content": "value = 1\\n",
            }, *([{"action": "status"}] * 7)],
        }
        with patch.object(server, "pc_agent_request", side_effect=[
            ({"ok": True, "results": None}, 200),
            ({"ok": True, "results": [{
                "step": "1/1 python_syntax", "ok": True, "checked_count": 1,
            }]}, 200),
        ]) as request, patch.object(server, "write_audit"):
            result = server.execute_pc_agent_plan(arguments)

        self.assertTrue(result["ok"])
        self.assertEqual(result["actions"], ["write_file", *(["status"] * 7), "python_syntax"])
        self.assertEqual(request.call_count, 2)
        self.assertEqual(len(request.call_args_list[0].args[1]["steps"]), 8)
        self.assertEqual(result["task_result"]["results"][0]["checked_count"], 1)

    def test_repair_loop_requires_a_successful_test_before_reporting_completion(self):
        def tool_call(action):
            return {"message": {"content": "", "tool_calls": [{
                "function": {"name": "run_safe_pc_task", "arguments": {
                    "title": "Repair and verify", "goal": "Fix the reported bug",
                    "steps": [{"action": action}],
                }},
            }]}}

        change = {
            "ok": True, "actions": ["write_file"], "changed_paths": ["server/fix.py"],
            "task_result": {"results": [{"step": "1/1 write_file", "ok": True}]},
        }
        successful_test = {
            "ok": True, "actions": ["test_file"], "changed_paths": [],
            "task_result": {"results": [{"step": "1/1 test_file", "ok": True}]},
        }
        failed_test = {
            "ok": False, "actions": ["test_file"], "changed_paths": [],
            "task_result": {"results": [{"step": "1/1 test_file", "ok": False}]},
        }
        status = {
            "ok": True, "actions": ["status"], "changed_paths": [],
            "task_result": {"results": [{"step": "1/1 status", "ok": True}]},
        }
        cases = (
            ([change, successful_test], [tool_call("test_file"), {"message": {"content": "Tests grün."}}], True),
            ([change, failed_test, status], [tool_call("test_file"), tool_call("status"), {"message": {"content": "Status geprüft."}}], False),
        )

        for outcomes, replies, expected_complete in cases:
            with self.subTest(expected_complete=expected_complete):
                response_streams = [
                    io.BytesIO(json.dumps(reply).encode("utf-8")) for reply in replies
                ]
                with patch.object(server, "execute_pc_agent_plan", side_effect=outcomes), \
                     patch.object(server.urllib.request, "urlopen", side_effect=response_streams):
                    result = server.run_safe_pc_task_conversation(
                        tool_call("write_file")["message"],
                        {
                            "model": "test-model", "tools": [],
                            "messages": [{"role": "user", "content": "Repair the bug."}],
                        },
                        "http://ollama.invalid", "test-model", server.time.monotonic() + 120,
                    )
                self.assertEqual(result["task_ok"], expected_complete)
                if not expected_complete:
                    self.assertIn("kein passender Test", result["message"]["content"])
                    self.assertNotIn("Tests grün", result["message"]["content"])

    def test_repair_loop_fills_only_the_user_named_flutter_test_path(self):
        first = {"content": "", "tool_calls": [{"function": {
            "name": "run_safe_pc_task",
            "arguments": {"title": "Run test", "goal": "Run selected Flutter test",
                           "steps": [{"action": "flutter_test"}]},
        }}]}
        executed = {
            "ok": True, "actions": ["flutter_test"], "changed_paths": [],
            "task_result": {"results": [{"step": "1/1 flutter_test", "ok": True, "exit_code": 0}]},
        }
        chat_request = {"messages": [{
            "role": "user", "content": "Führe app/test/layout_system_test.dart aus.",
        }]}
        reply = io.BytesIO(json.dumps({"message": {"content": "Der Test ist bestanden."}}).encode())
        with patch.object(server, "execute_pc_agent_plan", return_value=executed) as execute, \
             patch.object(server.urllib.request, "urlopen", return_value=reply):
            result = server.run_safe_pc_task_conversation(
                first, chat_request, "http://ollama.invalid", "test-model",
                server.time.monotonic() + 60,
            )
        self.assertTrue(result["task_ok"])
        self.assertEqual(
            execute.call_args.args[0]["steps"],
            [{"action": "flutter_test", "path": "app/test/layout_system_test.dart"}],
        )

    def test_removes_content_from_git_status(self):
        self.assertEqual(
            normalize_pc_agent_task_steps([
                {"action": "git_status", "content": "unneeded"}
            ]),
            [{"action": "git_status"}],
        )

    def test_preserves_write_file_content(self):
        step = {
            "action": "write_file",
            "path": "probe.txt",
            "content": "hello",
        }
        self.assertEqual(normalize_pc_agent_task_steps([step]), [step])

    def test_preserves_replace_text_fields_and_test_file_path(self):
        steps = [
            {"action": "replace_text", "path": "server/server.py", "old_text": "before", "new_text": "after"},
            {"action": "test_file", "path": "server/test_ai_memory.py", "content": "irrelevant"},
            {"action": "flutter_test", "path": "app/test/widget_test.dart", "content": "irrelevant"},
        ]
        self.assertEqual(
            normalize_pc_agent_task_steps(steps),
            [
                steps[0],
                {"action": "test_file", "path": "server/test_ai_memory.py"},
                {"action": "flutter_test", "path": "app/test/widget_test.dart"},
            ],
        )

    def test_preserves_unknown_fields(self):
        step = {
            "action": "git_status",
            "description": "unexpected",
        }
        self.assertEqual(normalize_pc_agent_task_steps([step]), [step])

    def test_does_not_modify_original_steps(self):
        original = [{"action": "git_status", "content": "extra"}]
        normalize_pc_agent_task_steps(original)
        self.assertEqual(
            original,
            [{"action": "git_status", "content": "extra"}],
        )

    def test_non_list_input_is_returned_unchanged(self):
        original = {"action": "git_status"}
        self.assertIs(normalize_pc_agent_task_steps(original), original)


if __name__ == "__main__":
    unittest.main()
