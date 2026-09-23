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

        self.assertEqual(
            notify.send_serverchan("title", "content", "https://example.invalid"), 0
        )

        self.assertFalse(post.call_args.kwargs["trust_env"])

    @mock.patch.object(notify, "send_serverchan")
    @mock.patch.object(notify.os, "fork", return_value=123)
    def test_notification_dispatch_returns_in_parent(self, fork, send_serverchan):
        notify.dispatch_notifications("title", "content", "https://example.invalid")

        fork.assert_called_once_with()
        send_serverchan.assert_not_called()


if __name__ == "__main__":
    unittest.main()
