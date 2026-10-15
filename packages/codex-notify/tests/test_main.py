import json
import os
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import codex_notify as notify


class NotifyTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        registry = mock.patch.object(notify, "homes_file", str(Path(directory.name) / "homes.json"))
        registry.start()
        self.addCleanup(registry.stop)

    def test_registry_overrides_stale_shell_environment_and_reloads(self):
        registry = Path(notify.homes_file)
        with mock.patch.dict(os.environ, {"CODEX_NOTIFY_HOMES": "/old/official:/old/tca"}):
            registry.write_text(json.dumps(["/new/official", "/new/tca", "/new/wcy", "/new/wcy"]))
            self.assertEqual(
                notify.codex_db_paths(),
                [
                    Path(home) / "state_5.sqlite"
                    for home in ["/new/official", "/new/tca", "/new/wcy"]
                ],
            )
            registry.write_text(json.dumps(["/new/official", "/new/future"]))
            self.assertEqual(notify.codex_db_paths()[-1], Path("/new/future/state_5.sqlite"))

    def test_invalid_registry_prevents_route_cleanup(self):
        for content in ["{", "[]", '["relative/home"]', '{"homes": []}']:
            with self.subTest(content=content), tempfile.TemporaryDirectory() as directory:
                Path(notify.homes_file).write_text(content)
                with mock.patch.object(notify, "state_dir", directory):
                    notify.save_state("keep", {"profile": "me"})
                    notify.cleanup_orphaned_state()
                    self.assertTrue(Path(notify.state_path("keep")).exists())

    def test_broken_registry_symlink_prevents_route_cleanup(self):
        Path(notify.homes_file).symlink_to(Path(notify.homes_file).with_name("missing.json"))
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.object(notify, "state_dir", directory):
                notify.save_state("keep", {"profile": "me"})
                notify.cleanup_orphaned_state()
                self.assertTrue(Path(notify.state_path("keep")).exists())

    def test_pick_labels_homes_and_keeps_thread_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            homes = [
                Path(directory) / name for name in [".codex-openai", ".codex-tca", ".codex-wcy"]
            ]
            for index, home in enumerate(homes):
                self.make_database(home, f"thread-{index}")
            Path(notify.homes_file).write_text(json.dumps(list(map(str, homes))))
            with (
                mock.patch.object(
                    notify, "fzf_select", side_effect=["thread-2\t[.codex-wcy] test", "me"]
                ) as select,
                mock.patch.object(notify, "load_routes", return_value={"me": {}}),
                mock.patch.object(notify, "cmd_route", return_value=0) as route,
            ):
                self.assertEqual(notify.cmd_pick(), 0)
                for home in homes:
                    self.assertIn(f"[{home.name}] test", select.call_args_list[0].args[1])
                route.assert_called_once_with(["route", "thread-2", "me"])

    def test_markdown_preserves_structure_and_collapses_blank_lines(self):
        content = "  first  \n\n\nsecond  \n"
        self.assertEqual(notify.wecom_markdown(content), "first\n\nsecond")

    def test_state_round_trip_is_keyed_by_thread(self):
        with tempfile.TemporaryDirectory() as directory:
            previous = notify.state_dir
            notify.state_dir = directory
            try:
                notify.save_state("thread-a", {"profile": "me"})
                self.assertEqual(notify.load_state("thread-a"), {"profile": "me"})
                self.assertEqual(notify.load_state("thread-b"), {})
            finally:
                notify.state_dir = previous

    def test_invalid_state_is_ignored(self):
        with tempfile.TemporaryDirectory() as directory:
            previous = notify.state_dir
            notify.state_dir = directory
            try:
                path = Path(notify.state_path("thread-a"))
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("not json", encoding="utf-8")
                self.assertEqual(notify.load_state("thread-a"), {})
            finally:
                notify.state_dir = previous

    @mock.patch.object(notify.httpx, "post")
    def test_serverchan_ignores_proxy_environment(self, post):
        post.return_value.status_code = 200
        post.return_value.json.return_value = {"code": 0}

        self.assertEqual(notify.send_serverchan("title", "content", "https://example.invalid"), 0)

        self.assertFalse(post.call_args.kwargs["trust_env"])

    @mock.patch.object(notify.httpx, "post")
    def test_serverchan_api_rejection_is_failure(self, post):
        post.return_value.json.return_value = {"code": 1, "message": "rejected"}

        self.assertEqual(notify.send_serverchan("title", "content", "https://example.invalid"), 1)

    def test_serverchan_retries_within_one_hook_dispatch(self):
        with tempfile.TemporaryDirectory() as directory:
            with (
                mock.patch.object(notify, "state_dir", directory),
                mock.patch.object(
                    notify, "serverchan_outbox", str(Path(directory) / "serverchan-outbox")
                ),
                mock.patch.object(
                    notify,
                    "load_routes",
                    return_value={"me": {"serverchan": "https://example.invalid"}},
                ),
                mock.patch.object(notify, "send_serverchan", side_effect=[1, 0]) as send,
                mock.patch.object(notify.time, "sleep") as sleep,
            ):
                notify.queue_serverchan("thread", "turn", "title", "content", "me")
                queued = list(Path(notify.serverchan_outbox).glob("*.json"))
                self.assertEqual(len(queued), 1)

                notify.drain_serverchan()
                self.assertFalse(queued[0].exists())
                self.assertEqual(send.call_count, 2)
                sleep.assert_called_once_with(notify.SERVERCHAN_RETRY_DELAYS[0])

    def test_serverchan_exhausted_retries_stay_queued_for_next_hook(self):
        with tempfile.TemporaryDirectory() as directory:
            with (
                mock.patch.object(notify, "state_dir", directory),
                mock.patch.object(
                    notify, "serverchan_outbox", str(Path(directory) / "serverchan-outbox")
                ),
                mock.patch.object(
                    notify,
                    "load_routes",
                    return_value={"me": {"serverchan": "https://example.invalid"}},
                ),
                mock.patch.object(notify, "send_serverchan", return_value=1) as send,
                mock.patch.object(notify.time, "sleep"),
                mock.patch.object(notify, "log") as log,
            ):
                notify.queue_serverchan("thread", "turn", "title", "content", "me")
                path = next(Path(notify.serverchan_outbox).glob("*.json"))

                notify.drain_serverchan()

                self.assertTrue(path.exists())
                self.assertEqual(send.call_count, 3)
                self.assertEqual(json.loads(path.read_text())["attempts"], 3)
                self.assertTrue(
                    any("retained for next hook" in call.args[0] for call in log.call_args_list)
                )

    def test_wecom_queue_requires_relay_on_host(self):
        with (
            mock.patch.object(notify, "stdin_json", return_value={"session_id": "thread"}),
            mock.patch.object(notify, "load_state", return_value={}),
            mock.patch.object(notify, "load_routes", return_value={"me": {"wecom": "user"}}),
            mock.patch.object(notify, "queue_wecom_push") as queue,
            mock.patch.object(notify, "dispatch_notifications"),
            mock.patch.object(notify, "log"),
        ):
            notify.cmd_notify(["notify", "Codex"])
            queue.assert_not_called()

            notify.cmd_notify(["notify", "Codex", "--wecom-relay"])
            queue.assert_called_once()

    @mock.patch.object(notify, "send_serverchan")
    @mock.patch.object(notify.os, "fork", return_value=123)
    def test_notification_dispatch_returns_in_parent(self, fork, send_serverchan):
        notify.dispatch_notifications("title", "content")

        fork.assert_called_once_with()
        send_serverchan.assert_not_called()

    def make_database(self, home, thread_id):
        home.mkdir()
        connection = sqlite3.connect(home / "state_5.sqlite")
        try:
            connection.execute("CREATE TABLE threads (id TEXT, title TEXT, updated_at INTEGER)")
            connection.execute("INSERT INTO threads VALUES (?, ?, ?)", (thread_id, "test", 1))
            connection.commit()
        finally:
            connection.close()

    def test_cleanup_preserves_routes_from_both_homes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            homes = [root / "official", root / "tca"]
            for home, thread in zip(homes, ["official-thread", "tca-thread"]):
                self.make_database(home, thread)
            with (
                mock.patch.dict(
                    os.environ, {"CODEX_NOTIFY_HOMES": os.pathsep.join(map(str, homes))}
                ),
                mock.patch.object(notify, "state_dir", str(root / "routes")),
                mock.patch.object(notify, "log"),
            ):
                for thread in ["official-thread", "tca-thread", "deleted"]:
                    notify.save_state(thread, {"profile": "me"})
                notify.cleanup_orphaned_state()
                self.assertTrue(Path(notify.state_path("official-thread")).exists())
                self.assertTrue(Path(notify.state_path("tca-thread")).exists())
                self.assertFalse(Path(notify.state_path("deleted")).exists())

    def test_unreadable_database_prevents_route_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            official = root / "official"
            self.make_database(official, "thread")
            broken = root / "broken"
            broken.mkdir()
            (broken / "state_5.sqlite").write_text("invalid sqlite")
            with (
                mock.patch.dict(
                    os.environ,
                    {"CODEX_NOTIFY_HOMES": os.pathsep.join(map(str, [official, broken]))},
                ),
                mock.patch.object(notify, "state_dir", str(root / "routes")),
            ):
                notify.save_state("unknown", {"profile": "me"})
                notify.cleanup_orphaned_state()
                self.assertTrue(Path(notify.state_path("unknown")).exists())

    def test_hook_argument_identifies_home_in_wecom_notification(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            mock.patch.object(notify, "stdin_json", return_value={"session_id": "thread"}),
            mock.patch.object(notify, "load_state", return_value={}),
            mock.patch.object(notify, "load_routes", return_value={"me": {"wecom": "user"}}),
            mock.patch.object(notify, "reply_outbox", str(Path(directory) / "outbox")),
            mock.patch.object(notify, "dispatch_notifications"),
            mock.patch.object(notify, "log"),
        ):
            home = str(Path(directory) / "tca")
            notify.cmd_notify(["notify", "Codex", "--codex-home", home, "--wecom-relay"])
            entry = json.loads(Path(notify.reply_outbox).read_text())
            self.assertEqual(entry["codex_home"], home)
            self.assertEqual(entry["thread"], "thread")


if __name__ == "__main__":
    unittest.main()
