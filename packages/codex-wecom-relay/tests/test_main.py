import asyncio
import json
import logging
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

from codex_wecom_relay import main as relay_module


class FakeWebSocket:
    def __init__(self, error=None):
        self.error = error
        self.messages = []

    async def send(self, message):
        if self.error:
            raise self.error
        self.messages.append(json.loads(message))


class RelayTests(unittest.IsolatedAsyncioTestCase):
    def make_relay(self, directory):
        return relay_module.Relay(
            {"bot_id": "bot", "secret": "secret"},
            "wss://example.invalid",
            directory,
            logging.getLogger("test"),
        )

    def test_app_server_unix_handshake_disables_compression(self):
        with patch.object(relay_module, "unix_connect") as connect:
            relay_module.AppServer("/tmp/app-server.sock").connect()

        connect.assert_called_once_with(
            "/tmp/app-server.sock", open_timeout=30, ping_interval=None, compression=None
        )

    def test_app_server_subscribes_before_starting_turn(self):
        app = relay_module.AppServer("/tmp/app-server.sock")
        with (
            patch.object(app, "initialize"),
            patch.object(app, "resume_thread") as resume,
            patch.object(app, "read_thread", return_value={"thread": {"status": {"type": "idle"}}}),
            patch.object(app, "start_turn") as start,
            patch.object(relay_module, "TURN_IDLE_SETTLE_SECONDS", 0),
            patch.object(
                app,
                "notifications",
                return_value=iter(
                    [
                        {
                            "method": "turn/completed",
                            "params": {"turn": {"id": "turn", "status": "completed"}},
                        }
                    ]
                ),
            ),
        ):
            start.side_effect = lambda *_: (
                {"turn": {"id": "turn"}} if resume.called else self.fail("thread was not resumed")
            )
            self.assertEqual(list(app.run_turn("thread", "reply")), [("done", "completed")])

        resume.assert_called_once_with("thread")
        start.assert_called_once_with("thread", "reply")

    def test_app_server_waits_for_idle_and_ignores_earlier_turn(self):
        app = relay_module.AppServer("/tmp/app-server.sock")
        statuses = iter(["active", "active", "idle"])
        with (
            patch.object(app, "initialize"),
            patch.object(app, "resume_thread"),
            patch.object(
                app,
                "read_thread",
                side_effect=lambda _: {"thread": {"status": {"type": next(statuses)}}},
            ),
            patch.object(app, "start_turn", return_value={"turn": {"id": "reply-turn"}}) as start,
            patch.object(relay_module, "TURN_IDLE_SETTLE_SECONDS", 0),
            patch.object(relay_module, "TURN_STATUS_POLL_SECONDS", 0),
            patch.object(
                app,
                "notifications",
                return_value=iter(
                    [
                        {
                            "method": "item/agentMessage/delta",
                            "params": {"turnId": "earlier-turn", "delta": "old"},
                        },
                        {
                            "method": "turn/completed",
                            "params": {"turn": {"id": "earlier-turn", "status": "completed"}},
                        },
                        {
                            "method": "item/agentMessage/delta",
                            "params": {"turnId": "reply-turn", "delta": "new"},
                        },
                        {
                            "method": "turn/completed",
                            "params": {"turn": {"id": "reply-turn", "status": "completed"}},
                        },
                    ]
                ),
            ),
        ):
            self.assertEqual(
                list(app.run_turn("thread", "reply")),
                [("queued", None), ("delta", "new"), ("done", "completed")],
            )
        start.assert_called_once_with("thread", "reply")

    async def test_failed_delivery_remains_in_processing_queue(self):
        with tempfile.TemporaryDirectory() as directory:
            relay = self.make_relay(directory)
            Path(relay.outbox).write_text(
                json.dumps({"thread": "thread", "chatid": "user", "content": "done"}) + "\n",
                encoding="utf-8",
            )

            with self.assertRaises(ConnectionError):
                await relay._process_outbox(FakeWebSocket(ConnectionError("offline")))

            self.assertTrue(Path(relay.outbox + ".processing").exists())

    async def test_successful_delivery_removes_processing_queue(self):
        with tempfile.TemporaryDirectory() as directory:
            relay = self.make_relay(directory)
            Path(relay.outbox).write_text(
                json.dumps({"thread": "thread", "chatid": "user", "content": "done"}) + "\n",
                encoding="utf-8",
            )
            websocket = FakeWebSocket()

            delivery = asyncio.create_task(relay._process_outbox(websocket))
            while not websocket.messages:
                await asyncio.sleep(0)
            request_id = websocket.messages[0]["headers"]["req_id"]
            relay._resolve_command({"headers": {"req_id": request_id}, "errcode": 0})
            await delivery

            self.assertEqual(websocket.messages[0]["cmd"], "aibot_send_msg")
            self.assertFalse(Path(relay.outbox + ".processing").exists())

    async def test_rejected_delivery_remains_in_processing_queue(self):
        with tempfile.TemporaryDirectory() as directory:
            relay = self.make_relay(directory)
            Path(relay.outbox).write_text(
                json.dumps({"thread": "thread", "chatid": "user", "content": "done"}) + "\n",
                encoding="utf-8",
            )
            websocket = FakeWebSocket()

            delivery = asyncio.create_task(relay._process_outbox(websocket))
            while not websocket.messages:
                await asyncio.sleep(0)
            request_id = websocket.messages[0]["headers"]["req_id"]
            relay._resolve_command(
                {
                    "headers": {"req_id": request_id},
                    "errcode": 40001,
                    "errmsg": "rejected",
                }
            )

            with self.assertRaises(RuntimeError):
                await delivery
            self.assertTrue(Path(relay.outbox + ".processing").exists())

    async def test_missing_ack_code_remains_in_processing_queue(self):
        with tempfile.TemporaryDirectory() as directory:
            relay = self.make_relay(directory)
            Path(relay.outbox).write_text(
                json.dumps({"thread": "thread", "chatid": "user", "content": "done"}) + "\n",
                encoding="utf-8",
            )
            websocket = FakeWebSocket()
            delivery = asyncio.create_task(relay._process_outbox(websocket))
            while not websocket.messages:
                await asyncio.sleep(0)
            request_id = websocket.messages[0]["headers"]["req_id"]
            relay._resolve_command({"headers": {"req_id": request_id}})

            with self.assertRaises(RuntimeError):
                await delivery
            self.assertTrue(Path(relay.outbox + ".processing").exists())

    def test_stream_id_is_stable(self):
        relay = self.make_relay("/tmp/unused-codex-wecom-relay-test")
        callback = {"headers": {"req_id": "request-id"}}
        self.assertEqual(relay._stream_id(callback), relay._stream_id(callback))

    def test_thread_provider_selects_dedicated_socket(self):
        relay = relay_module.Relay(
            {"bot_id": "bot", "secret": "secret"},
            "wss://example.invalid",
            "/tmp/unused-codex-wecom-relay-test",
            logging.getLogger("test"),
            {"tca": "/tmp/tca.sock"},
        )

        with patch.object(relay_module, "AppServer") as app_server:
            metadata = app_server.return_value
            metadata.read_thread.return_value = {"thread": {"modelProvider": "tca"}}

            relay._app_for_thread("thread")

            app_server.assert_any_call()
            app_server.assert_called_with("/tmp/tca.sock")
            metadata.close.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
