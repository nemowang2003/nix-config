import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from codex_notify import main as notify


class NotifyTests(unittest.TestCase):
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

        self.assertEqual(
            notify.send_serverchan("title", "content", "https://example.invalid"), 0
        )

        self.assertFalse(post.call_args.kwargs["trust_env"])

    @mock.patch.object(notify.httpx, "post")
    def test_serverchan_api_rejection_is_failure(self, post):
        post.return_value.json.return_value = {"code": 1, "message": "rejected"}

        self.assertEqual(
            notify.send_serverchan("title", "content", "https://example.invalid"), 1
        )

    def test_serverchan_retries_within_one_hook_dispatch(self):
        with tempfile.TemporaryDirectory() as directory:
            with (
                mock.patch.object(notify, "state_dir", directory),
                mock.patch.object(
                    notify, "serverchan_outbox", str(Path(directory) / "serverchan-outbox")
                ),
                mock.patch.object(
                    notify, "load_routes", return_value={"me": {"serverchan": "https://example.invalid"}}
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
                    notify, "load_routes", return_value={"me": {"serverchan": "https://example.invalid"}}
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
                self.assertTrue(any("retained for next hook" in call.args[0] for call in log.call_args_list))

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


if __name__ == "__main__":
    unittest.main()
