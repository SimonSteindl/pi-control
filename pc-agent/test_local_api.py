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

    def test_api_binds_only_loopback(self):
        # Guard against accidentally changing the listener to all network interfaces.
        source = MODULE_PATH.read_text(encoding="utf-8")
        self.assertIn('ThreadingHTTPServer(("127.0.0.1", PORT)', source)
        self.assertNotIn('ThreadingHTTPServer(("0.0.0.0", PORT)', source)


if __name__ == "__main__":
    unittest.main()
