import asyncio
import importlib.util
import json
import logging
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("main.py")
SPEC = importlib.util.spec_from_file_location("codex_wecom_relay", MODULE_PATH)
relay_module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(relay_module)


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
