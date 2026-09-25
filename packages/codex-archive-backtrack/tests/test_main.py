import json
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest import mock


from codex_archive_backtrack import main as archive


def event(payload, timestamp="2026-01-01T00:00:00Z"):
    return json.dumps(
        {"type": "response_item", "timestamp": timestamp, "payload": payload}
    ) + "\n"


class ArchiveBacktrackTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.db = self.root / "state_5.sqlite"
        with sqlite3.connect(self.db) as connection:
            connection.execute(
                "CREATE TABLE threads "
                "(id TEXT PRIMARY KEY, rollout_path TEXT NOT NULL, archived INTEGER NOT NULL)"
            )

    def tearDown(self):
        self.temporary.cleanup()

    def add_parent(self, suffix: str, archived: int = 0):
        parent = self.root / "parent.jsonl"
        prefix = event({"type": "message", "role": "assistant"})
        parent.write_text(prefix + suffix, encoding="utf-8")
        with sqlite3.connect(self.db) as connection:
            connection.execute(
                "INSERT INTO threads VALUES (?, ?, ?)",
                ("parent", str(parent), archived),
            )
        return parent, len(prefix.encode())

    def hook_input(self, cutoff: int):
        child = self.root / "child.jsonl"
        child.write_text(
            json.dumps(
                {
                    "type": "session_meta",
                    "payload": {
                        "id": "child",
                        "forked_from_id": "parent",
                        "timestamp": "2026-01-01T00:00:01Z",
                        "history_base": {"end_byte_offset": cutoff},
                    },
                }
            )
            + "\n",
            encoding="utf-8",
        )
        return {
            "hook_event_name": "SessionStart",
            "source": "fork",
            "session_id": "child",
            "transcript_path": str(child),
        }

    def test_backtrack_omits_user_message(self):
        _, cutoff = self.add_parent(
            event({"type": "message", "role": "user"})
            + event({"type": "message", "role": "assistant"})
        )
        self.assertEqual(
            archive.parent_for_backtrack(self.hook_input(cutoff), self.db), "parent"
        )

    def test_parent_messages_after_fork_do_not_trigger_archive(self):
        _, cutoff = self.add_parent(
            event({"type": "message", "role": "user"}, "2026-01-01T00:00:02Z")
        )

        self.assertIsNone(
            archive.parent_for_backtrack(self.hook_input(cutoff), self.db)
        )

    def test_complete_fork_ignores_trailing_non_user_events(self):
        _, cutoff = self.add_parent(
            json.dumps({"type": "event_msg", "payload": {"type": "token_count"}})
            + "\n"
        )
        self.assertIsNone(
            archive.parent_for_backtrack(self.hook_input(cutoff), self.db)
        )

    def test_non_fork_session_is_ignored(self):
        _, cutoff = self.add_parent(event({"type": "message", "role": "user"}))
        hook_input = self.hook_input(cutoff)
        hook_input["source"] = "resume"
        self.assertIsNone(archive.parent_for_backtrack(hook_input, self.db))

    @mock.patch.object(archive.subprocess, "run")
    def test_archive_uses_official_cli(self, run):
        run.return_value.returncode = 0

        archive.archive_thread("/bin/codex", "parent")

        run.assert_called_once_with(
            ["/bin/codex", "archive", "parent"],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )

    @mock.patch.object(archive.subprocess, "run")
    def test_archive_targets_forking_app_server(self, run):
        run.return_value.returncode = 0

        archive.archive_thread(
            "/bin/codex", "parent", "unix:///home/nemo/.codex/openai.sock"
        )

        run.assert_called_once_with(
            [
                "/bin/codex",
                "archive",
                "--remote",
                "unix:///home/nemo/.codex/openai.sock",
                "parent",
            ],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )


if __name__ == "__main__":
    unittest.main()
