#!/usr/bin/env python3

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path


def load_server():
    configured_path = os.environ.get("PI_CONTROL_SERVER_PATH")
    candidates = [
        Path(configured_path) if configured_path else None,
        Path(__file__).resolve().with_name("server.py"),
        Path(__file__).resolve().parents[1] / "deploy" / "pi-server" / "server.py",
    ]
    server_path = next((path for path in candidates if path and path.is_file()), None)
    if server_path is None:
        raise FileNotFoundError("Pi-Control server.py was not found")
    spec = importlib.util.spec_from_file_location("pi_control_server_memory_test", server_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class AiMemoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="pi-control-ai-memory-test-")
        self.temp_path = Path(self.temp.name)
        self.server = load_server()
        self.server.BASE_DIR = self.temp_path
        self.server.AI_MEMORY_DB_FILE = self.temp_path / "ai_memory.db"

    def tearDown(self):
        self.temp.cleanup()

    def test_memories_are_persistent_and_isolated_by_user(self):
        saved, error = self.server.save_ai_memory(11, "Die App läuft auf meinem Raspberry Pi.")
        self.assertTrue(saved, error)
        self.assertEqual(
            self.server.get_ai_memories(11)[0]["memory"],
            "Die App läuft auf meinem Raspberry Pi.",
        )
        self.assertEqual(self.server.get_ai_memories(12), [])

    def test_duplicate_memory_is_not_added_twice(self):
        self.assertTrue(self.server.save_ai_memory(11, "Lieblingsmodell: qwen3:1.7b")[0])
        self.assertTrue(self.server.save_ai_memory(11, "Lieblingsmodell: qwen3:1.7b")[0])
        self.assertEqual(len(self.server.get_ai_memories(11)), 1)

    def test_credentials_are_rejected(self):
        saved, error = self.server.save_ai_memory(11, "API key: abc123")
        self.assertFalse(saved)
        self.assertIn("Geheimnisse", error)
        self.assertEqual(self.server.get_ai_memories(11), [])

    def test_memory_length_is_bounded(self):
        saved, error = self.server.save_ai_memory(11, "x" * 1001)
        self.assertFalse(saved)
        self.assertIn("1000", error)

    def test_explicit_memory_command_extracts_only_the_requested_text(self):
        self.assertEqual(
            self.server.extract_explicit_memory_request("Merk dir 123"),
            "123",
        )
        self.assertEqual(
            self.server.extract_explicit_memory_request("Merke dir: Pi-Control"),
            "Pi-Control",
        )
        self.assertIsNone(
            self.server.extract_explicit_memory_request("Was sollst du dir merken?")
        )

    def test_memory_recall_questions_are_detected_deterministically(self):
        for prompt in (
            "Was sollst du dir merken?",
            "Was hast du dir gemerkt?",
            "Zeig mir deine Erinnerungen",
            "Was steht in deinem Gedächtnis?",
        ):
            with self.subTest(prompt=prompt):
                self.assertTrue(self.server.is_ai_memory_recall_request(prompt))
        self.assertFalse(
            self.server.is_ai_memory_recall_request("Wie warm ist mein Raspberry Pi?")
        )

    def test_pc_action_detector_only_matches_direct_commands(self):
        self.assertTrue(self.server.is_explicit_pc_action_request("Öffne den Browser"))
        self.assertTrue(self.server.is_explicit_pc_action_request("Bitte starte den Editor"))
        self.assertFalse(self.server.is_explicit_pc_action_request("Wie öffne ich den Browser?"))
        self.assertFalse(self.server.is_explicit_pc_action_request("Erkläre mir den PC-Agent"))


if __name__ == "__main__":
    unittest.main()
