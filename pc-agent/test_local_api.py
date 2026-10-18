#!/usr/bin/env python3
import importlib.util
import tempfile
import unittest
from pathlib import Path

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
if __name__ == "__main__":
    unittest.main()
