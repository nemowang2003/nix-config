import asyncio
import json
import logging
import tempfile
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, patch

import codex_wecom_relay as relay_module
from websockets.asyncio.server import unix_serve


async def async_items(items):
    for item in items:
        yield item


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
            "/tmp/openai.sock",
        )

    async def test_app_server_unix_handshake_disables_compression(self):
        with patch.object(relay_module, "unix_connect", new_callable=AsyncMock) as connect:
            await relay_module.AppServer("/tmp/app-server.sock").connect()

        connect.assert_called_once_with(
            "/tmp/app-server.sock",
            open_timeout=30,
            ping_interval=None,
            compression=None,
            max_size=None,
        )

    async def test_app_server_subscribes_before_queueing_reply(self):
        app = relay_module.AppServer("/tmp/app-server.sock")
        with (
            patch.object(app, "initialize"),
            patch.object(app, "resume_thread") as resume,
            patch.object(app, "queue_turn") as enqueue,
            patch.object(relay_module.secrets, "token_hex", return_value="reply-id"),
            patch.object(
                app,
                "notifications",
                return_value=async_items(
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
                [item async for item in app.run_turn("thread", "reply")],
                [("queued", None), ("delta", "answer"), ("done", "completed")],
            )

        resume.assert_called_once_with("thread")
        enqueue.assert_called_once_with("thread", "reply", "reply-id")

    async def test_app_server_ignores_earlier_turn(self):
        app = relay_module.AppServer("/tmp/app-server.sock")
        with (
            patch.object(app, "initialize"),
            patch.object(app, "resume_thread"),
            patch.object(app, "queue_turn", return_value={"queuedSubmission": {"id": "queued-id"}}),
            patch.object(relay_module.secrets, "token_hex", return_value="reply-id"),
            patch.object(
                app,
                "notifications",
                return_value=async_items(
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
                [item async for item in app.run_turn("thread", "reply")],
                [("queued", None), ("delta", "new"), ("done", "completed")],
            )

    async def test_request_retains_notifications_before_response(self):
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
            await app.queue_turn("thread", "reply", "reply-id")
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
            self.assertEqual(await anext(app.notifications()), notification)

    async def test_turn_over_unix_websocket_retains_early_notifications(self):
        async def serve(websocket):
            async for raw in websocket:
                request = json.loads(raw)
                if "id" not in request:
                    continue
                result = {}
                if request["method"] == "thread/queue/add":
                    client_id = request["params"]["clientUserMessageId"]
                    messages = [
                        {
                            "method": "item/started",
                            "params": {
                                "turnId": "reply-turn",
                                "item": {"type": "userMessage", "clientId": client_id},
                            },
                        },
                        {
                            "method": "item/agentMessage/delta",
                            "params": {
                                "turnId": "other-turn",
                                "delta": "ignore",
                            },
                        },
                        {
                            "method": "item/agentMessage/delta",
                            "params": {
                                "turnId": "reply-turn",
                                "delta": "answer",
                            },
                        },
                        {
                            "method": "turn/completed",
                            "params": {
                                "turn": {"id": "reply-turn", "status": "completed"},
                            },
                        },
                    ]
                    for message in messages:
                        await websocket.send(json.dumps(message))
                    result = {"queuedSubmission": {"id": "queued-id"}}
                await websocket.send(json.dumps({"id": request["id"], "result": result}))

        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / "app.sock")
            async with unix_serve(serve, path):
                app = relay_module.AppServer(path)
                await app.connect()
                try:
                    result = await asyncio.wait_for(self.collect_turn(app), timeout=2)
                finally:
                    await app.close()
        self.assertEqual(result, [("queued", None), ("delta", "answer"), ("done", "completed")])

    async def collect_turn(self, app):
        return [item async for item in app.run_turn("thread", "reply")]

    async def test_cancelling_stream_closes_app_server_and_releases_submission(self):
        started = asyncio.Event()

        async def turn(*_args):
            yield ("queued", None)
            started.set()
            await asyncio.Event().wait()

        with tempfile.TemporaryDirectory() as directory:
            relay = self.make_relay(directory)
            app = relay_module.AppServer("/tmp/unused.sock")
            with (
                patch.object(relay, "_app_for_thread", return_value=app),
                patch.object(app, "connect"),
                patch.object(app, "close") as close,
                patch.object(app, "run_turn", side_effect=turn),
            ):
                running = asyncio.create_task(
                    relay._run_turn(FakeWebSocket(), {}, "thread", "reply")
                )
                try:
                    await asyncio.wait_for(started.wait(), timeout=1)
                    self.assertFalse(relay._submission_lock.locked())
                finally:
                    running.cancel()
                    await asyncio.gather(running, return_exceptions=True)
                close.assert_awaited_once_with()
                self.assertFalse(relay._submission_lock.locked())

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

    async def test_thread_provider_selects_dedicated_socket(self):
        relay = relay_module.Relay(
            {"bot_id": "bot", "secret": "secret"},
            "wss://example.invalid",
            "/tmp/unused-codex-wecom-relay-test",
            logging.getLogger("test"),
            "/tmp/openai.sock",
            {"tca": "/tmp/tca.sock"},
        )

        with patch.object(relay_module, "AppServer") as app_server:
            metadata = app_server.return_value
            for name in ("connect", "initialize", "read_thread", "close"):
                setattr(metadata, name, AsyncMock())
            metadata.read_thread.return_value = {"thread": {"modelProvider": "tca"}}

            await relay._app_for_thread("thread")

            app_server.assert_any_call("/tmp/openai.sock")
            app_server.assert_called_with("/tmp/tca.sock")
            metadata.close.assert_called_once_with()

    async def test_default_provider_uses_explicit_socket(self):
        relay = self.make_relay("/tmp/unused-codex-wecom-relay-test")
        with patch.object(relay_module, "AppServer") as app_server:
            await relay._app_for_thread("thread")
            app_server.assert_called_once_with("/tmp/openai.sock")


if __name__ == "__main__":
    unittest.main()
