import json
import socket
import sqlite3
import tempfile
import unittest
from pathlib import Path

from codex_home_migrate import check_migration, migrate


class MigrationTests(unittest.TestCase):
    def test_preserves_auth_and_history_and_rebases_database_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            old, new = root / ".codex", root / ".codex-openai"
            old.mkdir()
            (old / "auth.json").write_text('{"token":"test-secret"}')
            sessions = old / "sessions"
            sessions.mkdir()
            history = '{"message":"keep the historical reference ~/.codex unchanged"}\n'
            (sessions / "session.jsonl").write_text(history)
            database = sqlite3.connect(old / "state_5.sqlite")
            database.execute("CREATE TABLE threads (id TEXT, rollout_path TEXT)")
            database.execute(
                "INSERT INTO threads VALUES (?, ?)", ("session", str(sessions / "session.jsonl"))
            )
            database.commit()
            database.close()
            recovery = old / "app-server-daemon"
            recovery.mkdir()
            (recovery / "loaded-threads.json").write_text(
                json.dumps({"path": str(sessions / "session.jsonl")})
            )
            snapshots = old / "shell_snapshots"
            snapshots.mkdir()
            (snapshots / "session.sh").write_text(f'export CODEX_HOME="{old}"\n')
            check_migration(old, new)
            self.assertTrue(old.exists())
            self.assertFalse(new.exists())
            migrate(old, new)
            self.assertEqual(
                (new / "shell_snapshots/session.sh").read_text(), f'export CODEX_HOME="{new}"\n'
            )
            self.assertFalse(old.exists())
            self.assertEqual((new / "auth.json").read_text(), '{"token":"test-secret"}')
            self.assertEqual((new / "sessions/session.jsonl").read_text(), history)
            database = sqlite3.connect(new / "state_5.sqlite")
            self.assertEqual(
                database.execute("SELECT rollout_path FROM threads").fetchone()[0],
                str(new / "sessions/session.jsonl"),
            )
            database.close()
            self.assertTrue((new / "home-migration-backup/state_5.sqlite").exists())
            self.assertEqual(
                json.loads((new / "app-server-daemon/loaded-threads.json").read_text())["path"],
                str(new / "sessions/session.jsonl"),
            )
            migrate(old, new)
            self.assertFalse(old.exists())

    def test_running_daemon_prevents_any_move(self):
        with tempfile.TemporaryDirectory() as directory:
            old, new = Path(directory) / ".codex", Path(directory) / ".codex-openai"
            control = old / "app-server-control"
            control.mkdir(parents=True)
            with socket.socket(socket.AF_UNIX) as server:
                server.bind(str(control / "server.sock"))
                server.listen()
                with self.assertRaisesRegex(RuntimeError, "running app-server"):
                    migrate(old, new)
            self.assertTrue(old.exists())
            self.assertFalse(new.exists())

    def test_refuses_to_merge_existing_homes(self):
        with tempfile.TemporaryDirectory() as directory:
            old, new = Path(directory) / ".codex", Path(directory) / ".codex-openai"
            old.mkdir()
            new.mkdir()
            with self.assertRaisesRegex(RuntimeError, "Both"):
                migrate(old, new)
            self.assertTrue(old.exists())

    def test_resumes_interrupted_migration_and_skips_missing_source(self):
        with tempfile.TemporaryDirectory() as directory:
            old, new = Path(directory) / ".codex", Path(directory) / ".codex-openai"
            migrate(old, new)
            self.assertFalse(new.exists())
            new.mkdir()
            (new / ".home-migration.json").write_text(json.dumps({"source": str(old)}))
            (new / "config.toml").write_text(f'log_dir = "{old}/log"\n')
            migrate(old, new)
            self.assertEqual((new / "config.toml").read_text(), f'log_dir = "{new}/log"\n')
            self.assertFalse((new / ".home-migration.json").exists())
