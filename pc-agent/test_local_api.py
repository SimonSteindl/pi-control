#!/usr/bin/env python3
import importlib.util
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

MODULE_PATH = Path(__file__).with_name("local_api.py")
SPEC = importlib.util.spec_from_file_location("pi_control_local_api_test", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class LocalApiSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="pi-control-agent-test-")
        self.workspace = Path(self.temp.name)
        (self.workspace / "inside.txt").write_text("hello", encoding="utf-8")

    def tearDown(self):
        self.temp.cleanup()

    def test_reads_file_inside_workspace(self):
        path = MODULE.safe_file(self.workspace, "inside.txt")
        self.assertEqual(path.read_text(encoding="utf-8"), "hello")

    def test_blocks_path_traversal(self):
        with self.assertRaises(ValueError):
            MODULE.safe_file(self.workspace, "../outside.txt")

    def test_blocks_missing_file(self):
        with self.assertRaises(ValueError):
            MODULE.safe_file(self.workspace, "missing.txt")

    def test_git_diff_endpoint_requires_and_passes_a_single_path(self):
        source = MODULE_PATH.read_text(encoding="utf-8")
        route = source.split('parsed.path == "/v1/git/diff":', 1)[1].split(
            'parsed.path == "/v1/file":', 1
        )[0]
        self.assertIn("validate_git_diff_path(supplied)", route)
        self.assertIn('"--no-ext-diff"', route)
        self.assertIn('"--no-textconv"', route)
        self.assertIn('"--", safe_path', route)
        self.assertNotIn('"diff", "--")', route)

    def test_git_diff_safe_plan_passes_the_validated_step_path(self):
        source = MODULE_PATH.read_text(encoding="utf-8")
        route = source.split('if action == "git_diff":', 1)[1].split(
            'if action == "read_file":', 1
        )[0]
        self.assertIn('"--", step["path"]', route)
        self.assertNotIn('"diff", "--")', route)

    def test_git_status_excludes_the_three_protected_paths(self):
        with patch.object(MODULE, "git_output", return_value={"ok": True}) as git_output:
            result = MODULE.safe_git_status(self.workspace)
        self.assertTrue(result["ok"])
        self.assertEqual(git_output.call_args.args[1:], (
            "--no-optional-locks", "status", "--short", "--branch", "--", ".",
            ":(exclude)history.json",
            ":(exclude)server/test_auth_api.py",
            ":(exclude)pc_agent_write_probe.txt",
        ))

    def test_listener_defaults_to_loopback_and_remote_needs_allowlist(self):
        source = MODULE_PATH.read_text(encoding="utf-8")
        self.assertIn('parser.add_argument("--bind-host", default="127.0.0.1"', source)
        self.assertIn("if not is_loopback and not allowed_clients:", source)
        self.assertIn("client_ip not in self.server.allowed_clients", source)

    def test_write_delete_and_command_require_explicit_approval(self):
        source = MODULE_PATH.read_text(encoding="utf-8")
        self.assertGreaterEqual(source.count('body.get("approved") is not True'), 3)
        self.assertIn('parsed.path == "/v1/file/write"', source)
        self.assertIn('parsed.path == "/v1/file/delete"', source)
        self.assertIn('parsed.path == "/v1/command"', source)
        self.assertIn("shell=False", source)
        self.assertIn('".pi-control-agent" / "backups"', source)
        self.assertIn('".pi-control-agent" / "trash"', source)


    def test_command_allowlist_contains_only_exact_commands(self):
        allowed = MODULE.ALLOWED_COMMANDS

        self.assertIn(("whoami",), allowed)
        self.assertIn(("uname", "-a"), allowed)
        self.assertNotIn(("python", "-c", "print(1)"), allowed)
        self.assertNotIn(("rm", "-rf", "/"), allowed)

    def test_command_allowlist_rejects_extra_arguments(self):
        allowed = MODULE.ALLOWED_COMMANDS

        self.assertNotIn(("whoami", "extra"), allowed)
        self.assertNotIn(("df", "-h", "/"), allowed)
    def test_command_allowlist_is_checked_before_execution(self):
        source = MODULE_PATH.read_text(encoding="utf-8")
        route = source.split('parsed.path == "/v1/command":', 1)[1]
        allowlist_check = route.index("tuple(command) not in ALLOWED_COMMANDS")
        execution = route.index("subprocess.run(")
        self.assertLess(allowlist_check, execution)
    def test_safe_workspace_write_creates_file_and_backs_up_overwrite(self):
        backup_root = self.workspace / "test-backups"
        result = MODULE.safe_workspace_write(self.workspace, "inside.txt", "changed", backup_root=backup_root)
        self.assertTrue(result["ok"])
        self.assertEqual((self.workspace / "inside.txt").read_text(encoding="utf-8"), "changed")
        backup = Path(result["backup"])
        self.assertTrue(backup.is_file())
        self.assertEqual(backup.read_text(encoding="utf-8"), "hello")
        created = MODULE.safe_workspace_write(self.workspace, "new.txt", "new", backup_root=backup_root)
        self.assertTrue(created["created"])
        self.assertIsNone(created["backup"])

    def test_safe_workspace_write_blocks_protected_and_internal_paths(self):
        for path in (
            "history.json", "server/test_auth_api.py", "pc_agent_write_probe.txt",
            ".git/config", ".venv/test.txt", "../outside.txt",
        ):
            with self.subTest(path=path), self.assertRaises(ValueError):
                MODULE.safe_workspace_write(self.workspace, path, "blocked", backup_root=self.workspace / "backups")

    def test_safe_file_blocks_all_protected_project_paths(self):
        for path in ("history.json", "server/test_auth_api.py", "pc_agent_write_probe.txt"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                MODULE.safe_file(self.workspace, path, workspace=self.workspace)

    def test_deletion_guard_blocks_protected_files_and_their_parent_directories(self):
        for path in ("history.json", "server/test_auth_api.py", "pc_agent_write_probe.txt", "."):
            with self.subTest(path=path), self.assertRaises(ValueError):
                MODULE.resolve_user_path(
                    self.workspace, path, workspace=self.workspace,
                    include_protected_parent_dirs=True,
                )

    def test_safe_workspace_write_requires_existing_parent_and_blocks_symlinks(self):
        with self.assertRaises(ValueError):
            MODULE.safe_workspace_write(self.workspace, "missing/new.txt", "x", backup_root=self.workspace / "backups")
        outside = self.workspace.parent / (self.workspace.name + "-outside")
        outside.write_text("outside", encoding="utf-8")
        link = self.workspace / "link.txt"
        try:
            link.symlink_to(outside)
            with self.assertRaises(ValueError):
                MODULE.safe_workspace_write(self.workspace, "link.txt", "no", backup_root=self.workspace / "backups")
        finally:
            link.unlink(missing_ok=True)
            outside.unlink(missing_ok=True)

    def test_safe_workspace_write_rejects_oversized_content(self):
        with self.assertRaises(ValueError):
            MODULE.safe_workspace_write(self.workspace, "large.txt", "x" * 20001, backup_root=self.workspace / "backups")

    def test_safe_workspace_replace_requires_one_exact_match_and_backs_up(self):
        source = self.workspace / "server" / "feature.py"
        source.parent.mkdir()
        source.write_text("first\nold value\nlast\n", encoding="utf-8")
        backups = self.workspace / "backups"
        result = MODULE.safe_workspace_replace(
            self.workspace, "server/feature.py", "old value", "new value",
            backup_root=backups,
        )
        self.assertTrue(result["ok"])
        self.assertEqual(result["replacements"], 1)
        self.assertEqual(source.read_text(encoding="utf-8"), "first\nnew value\nlast\n")
        self.assertEqual(Path(result["backup"]).read_text(encoding="utf-8"), "first\nold value\nlast\n")
        with self.assertRaisesRegex(ValueError, "genau einmal"):
            MODULE.safe_workspace_replace(self.workspace, "server/feature.py", "missing", "x", backup_root=backups)
        source.write_text("same\nsame\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "genau einmal"):
            MODULE.safe_workspace_replace(self.workspace, "server/feature.py", "same", "x", backup_root=backups)

    def test_safe_workspace_replace_blocks_protected_and_symlink_paths(self):
        for path in ("history.json", "server/test_auth_api.py", "pc_agent_write_probe.txt", ".git/config", ".venv/test.py"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                MODULE.safe_workspace_replace(self.workspace, path, "old", "new")
        outside = self.workspace.parent / (self.workspace.name + "-replace-outside.py")
        outside.write_text("old", encoding="utf-8")
        link = self.workspace / "linked.py"
        try:
            link.symlink_to(outside)
            with self.assertRaises(ValueError):
                MODULE.safe_workspace_replace(self.workspace, "linked.py", "old", "new")
        finally:
            link.unlink(missing_ok=True)
            outside.unlink(missing_ok=True)

    def test_run_project_test_runs_only_named_project_test_files(self):
        test_file = self.workspace / "server" / "test_generated.py"
        test_file.parent.mkdir()
        test_file.write_text("print('safe test')\n", encoding="utf-8")
        result = MODULE.run_project_test(self.workspace, "server/test_generated.py")
        self.assertTrue(result["ok"])
        self.assertEqual(result["exit_code"], 0)
        self.assertIn("safe test", result["output"])
        for path in (
            "server/test_auth_api.py", "history.json", "pc_agent_write_probe.txt",
            "../server/test_ai_memory.py", "server/server.py", "other/test_demo.py",
        ):
            with self.subTest(path=path), self.assertRaises(ValueError):
                MODULE.run_project_test(self.workspace, path)

    def test_python_syntax_parses_sources_without_running_them_and_reports_locations(self):
        source_root = self.workspace / "server"
        source_root.mkdir()
        (source_root / "valid.py").write_text("value = 1\n", encoding="utf-8")
        (source_root / "broken.py").write_text("if True print('bad')\n", encoding="utf-8")
        (source_root / "test_ignored.py").write_text("if True print('ignored')\n", encoding="utf-8")
        (source_root / "TestHelper.py").write_text("if True print('ignored')\n", encoding="utf-8")
        (source_root / "ignored_test.PY").write_text("if True print('ignored')\n", encoding="utf-8")
        (source_root / "__pycache__").mkdir()
        (source_root / "__pycache__" / "ignored.py").write_text(
            "if True print('ignored')\n", encoding="utf-8"
        )
        (source_root / "Tests").mkdir()
        (source_root / "Tests" / "ignored.py").write_text(
            "if True print('ignored')\n", encoding="utf-8"
        )
        (self.workspace / "pc_agent").mkdir()
        (self.workspace / "pc_agent" / "marker.py").write_text(
            "from pathlib import Path\nPath('side-effect-marker').write_text('ran')\n",
            encoding="utf-8",
        )

        result = MODULE.check_python_syntax(self.workspace)

        self.assertFalse(result["ok"])
        self.assertEqual(result["exit_code"], 1)
        self.assertIn("server/valid.py", result["checked_files"])
        self.assertIn("pc_agent/marker.py", result["checked_files"])
        self.assertNotIn("server/test_ignored.py", result["checked_files"])
        self.assertNotIn("server/TestHelper.py", result["checked_files"])
        self.assertNotIn("server/ignored_test.PY", result["checked_files"])
        self.assertNotIn("server/__pycache__/ignored.py", result["checked_files"])
        self.assertNotIn("server/Tests/ignored.py", result["checked_files"])
        self.assertEqual(
            result["errors"],
            [{"path": "server/broken.py", "line": 1, "column": 9,
              "error": "invalid syntax"}],
        )
        self.assertFalse((self.workspace / "side-effect-marker").exists())

        (source_root / "broken.py").write_text("value = 2\n", encoding="utf-8")
        success = MODULE.check_python_syntax(self.workspace)
        self.assertTrue(success["ok"])
        self.assertEqual(success["exit_code"], 0)
        self.assertEqual(success["errors"], [])

    def test_flutter_test_runs_only_one_existing_app_test_with_fixed_arguments(self):
        app = self.workspace / "app"
        test_file = app / "test" / "features" / "library_test.dart"
        test_file.parent.mkdir(parents=True)
        (app / "pubspec.yaml").write_text("name: test_app\n", encoding="utf-8")
        test_file.write_text("void main() {}\n", encoding="utf-8")
        completed = SimpleNamespace(returncode=0, stdout="00:01 +1: All tests passed!\n")
        with patch.object(MODULE.shutil, "which", return_value="/usr/bin/flutter"), \
             patch.object(MODULE.subprocess, "run", return_value=completed) as run:
            result = MODULE.run_flutter_test(
                self.workspace, "app/test/features/library_test.dart"
            )

        self.assertTrue(result["ok"])
        self.assertEqual(result["exit_code"], 0)
        self.assertIn("All tests passed", result["output"])
        self.assertEqual(run.call_args.args[0], [
            "/usr/bin/flutter", "test", "--no-pub", "--reporter", "compact",
            "test/features/library_test.dart",
        ])
        self.assertEqual(run.call_args.kwargs["cwd"], app)
        self.assertIs(run.call_args.kwargs["shell"], False)
        for path in (
            "app/lib/main.dart", "server/test_example.py", "app/test/widget.dart",
            "app/test/../lib/main_test.dart", "../app/test/widget_test.dart",
        ):
            with self.subTest(path=path), self.assertRaises(ValueError):
                MODULE.run_flutter_test(self.workspace, path)

    def test_flutter_test_reports_missing_flutter_and_does_not_execute_anything(self):
        app = self.workspace / "app"
        app.mkdir()
        (app / "pubspec.yaml").write_text("name: test_app\n", encoding="utf-8")
        test_file = app / "test" / "widget_test.dart"
        test_file.parent.mkdir()
        test_file.write_text("void main() {}\n", encoding="utf-8")
        with patch.dict(MODULE.os.environ, {"HOME": str(self.workspace / "no-flutter-home")}), \
             patch.object(MODULE.shutil, "which", return_value=None), \
             patch.object(MODULE.subprocess, "run") as run:
            result = MODULE.run_flutter_test(self.workspace, "app/test/widget_test.dart")
        self.assertFalse(result["ok"])
        self.assertEqual(result["exit_code"], 127)
        self.assertIn("Flutter ist", result["error"])
        run.assert_not_called()

    def test_flutter_test_finds_a_user_local_sdk_without_requiring_path_changes(self):
        home = self.workspace / "home"
        flutter = home / ".local" / "share" / "flutter" / "bin" / "flutter"
        flutter.parent.mkdir(parents=True)
        flutter.write_text("", encoding="utf-8")
        flutter.chmod(0o755)
        app = self.workspace / "app"
        app.mkdir()
        (app / "pubspec.yaml").write_text("name: test_app\n", encoding="utf-8")
        test_file = app / "test" / "widget_test.dart"
        test_file.parent.mkdir()
        test_file.write_text("void main() {}\n", encoding="utf-8")
        completed = SimpleNamespace(returncode=0, stdout="passed")
        with patch.dict(MODULE.os.environ, {"HOME": str(home)}), \
             patch.object(MODULE.shutil, "which", return_value=None), \
             patch.object(MODULE.subprocess, "run", return_value=completed) as run:
            result = MODULE.run_flutter_test(self.workspace, "app/test/widget_test.dart")
        self.assertTrue(result["ok"])
        self.assertEqual(run.call_args.args[0][0], str(flutter))


if __name__ == "__main__":
    unittest.main()
