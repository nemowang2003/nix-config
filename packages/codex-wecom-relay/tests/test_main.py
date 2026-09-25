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


class FakeCallbackWebSocket(FakeWebSocket):
    def __init__(self):
        super().__init__()
        self.incoming = asyncio.Queue()

    def __aiter__(self):
        return self

    async def __anext__(self):
        return await self.incoming.get()


class FakeConnection:
    def __init__(self, websocket):
        self.websocket = websocket

    async def __aenter__(self):
        return self.websocket

    async def __aexit__(self, *_args):
        return False


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

    def test_app_server_subscribes_before_queueing_reply(self):
        app = relay_module.AppServer("/tmp/app-server.sock")
        with (
            patch.object(app, "initialize"),
            patch.object(app, "resume_thread") as resume,
            patch.object(app, "queue_turn") as enqueue,
            patch.object(relay_module.secrets, "token_hex", return_value="reply-id"),
            patch.object(
                app,
                "notifications",
                return_value=iter(
                    [
                        {
                            "method": "item/started",
                            "params": {
                                "turnId": "reply-turn",
                                "item": {"type": "userMessage", "clientId": "reply-id"},
                            },
                        },
                        {
                            "method": "item/agentMessage/delta",
                            "params": {"turnId": "reply-turn", "delta": "answer"},
                        },
                        {
                            "method": "turn/completed",
                            "params": {"turn": {"id": "reply-turn", "status": "completed"}},
                        },
                    ]
                ),
            ),
        ):
            enqueue.side_effect = lambda *_: (
                {"queuedSubmission": {"id": "queued-id"}}
                if resume.called
                else self.fail("thread was not resumed")
            )
            self.assertEqual(
                list(app.run_turn("thread", "reply")),
                [("queued", None), ("delta", "answer"), ("done", "completed")],
            )

        resume.assert_called_once_with("thread")
        enqueue.assert_called_once_with("thread", "reply", "reply-id")

    def test_app_server_ignores_earlier_turn(self):
        app = relay_module.AppServer("/tmp/app-server.sock")
        with (
            patch.object(app, "initialize"),
            patch.object(app, "resume_thread"),
            patch.object(app, "queue_turn", return_value={"queuedSubmission": {"id": "queued-id"}}),
            patch.object(relay_module.secrets, "token_hex", return_value="reply-id"),
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
                            "method": "item/started",
                            "params": {
                                "turnId": "reply-turn",
                                "item": {"type": "userMessage", "clientId": "reply-id"},
                            },
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

    def test_request_retains_notifications_before_response(self):
        app = relay_module.AppServer("/tmp/app-server.sock")
        notification = {"method": "item/started", "params": {"turnId": "reply-turn"}}
        with (
            patch.object(app, "_send_json") as send,
            patch.object(
                app,
                "_receive_json",
                side_effect=[
                    notification,
                    {"id": 1, "result": {"queuedSubmission": {"id": "queued-id"}}},
                ],
            ),
        ):
            app.queue_turn("thread", "reply", "reply-id")
            send.assert_called_once_with(
                {
                    "method": "thread/queue/add",
                    "id": 1,
                    "params": {
                        "threadId": "thread",
                        "input": [{"type": "text", "text": "reply"}],
                        "clientUserMessageId": "reply-id",
                    },
                }
            )
            self.assertEqual(next(app.notifications()), notification)

    async def test_callbacks_are_handled_while_earlier_reply_is_running(self):
        with tempfile.TemporaryDirectory() as directory:
            relay = self.make_relay(directory)
            websocket = FakeCallbackWebSocket()
            second_started = asyncio.Event()
            first_finished = asyncio.Event()

            async def handle(_ws, callback):
                if callback["body"]["msgid"] == "first":
                    await first_finished.wait()
                else:
                    second_started.set()

            with (
                patch.object(relay_module, "connect", return_value=FakeConnection(websocket)),
                patch.object(relay, "_handle_callback", side_effect=handle),
            ):
                running = asyncio.create_task(relay._run_once())
                try:
                    for msgid in ("first", "second"):
                        await websocket.incoming.put(
                            json.dumps({"cmd": "aibot_msg_callback", "body": {"msgid": msgid}})
                        )
                    await asyncio.wait_for(second_started.wait(), timeout=1)
                finally:
                    first_finished.set()
                    running.cancel()
                    await asyncio.gather(running, return_exceptions=True)

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
