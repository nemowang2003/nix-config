import asyncio
import json
import logging
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, Mock, patch

import codex_wecom_relay as relay_module
from websockets.asyncio.server import unix_serve


async def async_items(items):
    for item in items:
        yield item


class FakeWebSocket:
    def __init__(self, error=None, relay=None):
        self.error = error
        self.relay = relay
        self.messages = []

    async def send(self, message):
        if self.error:
            raise self.error
        payload = json.loads(message)
        self.messages.append(payload)
        if payload.get("cmd") == "aibot_respond_msg" and payload["body"].get("msgtype") == "stream":
            ack = {"headers": payload["headers"], "errcode": 0}
            if self.relay:
                self.relay._resolve_command(ack)
            elif isinstance(self, FakeCallbackWebSocket):
                await self.incoming.put(json.dumps(ack))


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
    def callback(self, relay, msgid="message", thread="thread", home_index=0):
        token = relay._new_token(thread, str(relay.codex_homes[home_index]))
        return {
            "headers": {"req_id": msgid},
            "body": {
                "msgid": msgid,
                "msgtype": "text",
                "from": {"userid": "user"},
                "quote": {"text": {"content": f"r#{token}"}},
                "text": {"content": "继续"},
            },
        }

    async def test_unknown_quote_never_falls_back_to_latest_notification(self):
        with tempfile.TemporaryDirectory() as directory:
            relay = self.make_relay(directory)
            callback = self.callback(relay)
            relay._last_push["user"] = {"token": relay._new_token("B")}
            callback["body"]["quote"]["text"]["content"] = "A 的旧流式消息，没有 token"
            with patch.object(relay, "_run_turn") as run:
                ws = FakeWebSocket(relay=relay)
                await relay._handle_callback(ws, callback)
                run.assert_not_called()
                self.assertIn("没有找到对应任务", ws.messages[-1]["body"]["markdown"]["content"])

    async def test_stream_token_routes_to_a_even_after_b_completion(self):
        with tempfile.TemporaryDirectory() as directory:
            relay = self.make_relay(directory)
            callback = self.callback(relay, thread="A")
            ws = FakeWebSocket(relay=relay)
            app = relay_module.AppServer("unused")
            with (
                patch.object(relay, "_app_for_thread", return_value=app),
                patch.object(app, "connect"),
                patch.object(
                    app,
                    "run_turn",
                    return_value=async_items(
                        [("queued", None), ("delta", "A 的回答"), ("done", "completed")]
                    ),
                ),
            ):
                await relay._handle_callback(ws, callback)
            contents = [m["body"]["stream"]["content"] for m in ws.messages]
            tokens = []
            for content in contents:
                match = relay_module.TOKEN_RE.search(content)
                assert match is not None
                tokens.append(match.group(1))
            self.assertEqual(len(set(tokens)), 1)
            relay._last_push["user"] = {"token": relay._new_token("B")}
            reply = self.callback(relay, msgid="reply")
            reply["body"]["quote"]["text"]["content"] = contents[1]
            with patch.object(relay, "_run_turn") as run:
                await relay._handle_callback(ws, reply)
                self.assertEqual(run.call_args.args[2], "A")
                self.assertEqual(run.call_args.args[4], str(relay.codex_homes[0]))

    async def test_rpc_deadline_includes_unending_notifications(self):
        async def serve(ws):
            request = json.loads(await ws.recv())
            self.assertEqual(request["method"], "initialize")
            await ws.send(json.dumps({"method": "unrelated", "params": {}}))
            await ws.wait_closed()

        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / "rpc.sock")
            async with await unix_serve(serve, path):
                app = relay_module.AppServer(path)
                await app.connect()
                try:
                    with patch.object(relay_module, "RPC_TIMEOUT", 0.03):
                        with self.assertRaises(TimeoutError):
                            await app.initialize()
                finally:
                    await app.close()

    async def test_stalled_initialization_only_blocks_same_home_and_thread(self):
        with tempfile.TemporaryDirectory() as directory:
            relay = self.make_relay(directory)
            stalled = asyncio.Event()
            release = asyncio.Event()
            starts = []

            async def make_app(thread, home):
                starts.append((str(home), thread))
                app = relay_module.AppServer("unused")
                app.connect = AsyncMock()

                async def turn(*_args):
                    if thread == "A":
                        stalled.set()
                        await release.wait()
                    yield ("queued", None)
                    yield ("done", "completed")

                app.run_turn = Mock(side_effect=turn)
                return app

            with patch.object(relay, "_app_for_thread", side_effect=make_app):
                first = asyncio.create_task(
                    relay._handle_callback(
                        FakeWebSocket(relay=relay), self.callback(relay, "first", "A")
                    )
                )
                await asyncio.wait_for(stalled.wait(), 1)
                same = asyncio.create_task(
                    relay._handle_callback(
                        FakeWebSocket(relay=relay), self.callback(relay, "same", "A")
                    )
                )
                try:
                    await asyncio.wait_for(
                        relay._handle_callback(
                            FakeWebSocket(relay=relay), self.callback(relay, "other-home", "B", 1)
                        ),
                        1,
                    )
                    await asyncio.wait_for(
                        relay._handle_callback(
                            FakeWebSocket(relay=relay), self.callback(relay, "other-thread", "C")
                        ),
                        1,
                    )
                    self.assertEqual(sum(thread == "A" for _, thread in starts), 1)
                    self.assertFalse(same.done())
                finally:
                    release.set()
                    await asyncio.gather(first, same)
                self.assertEqual(sum(thread == "A" for _, thread in starts), 2)

    async def test_rejected_submission_can_retry_same_msgid_after_restart(self):
        with tempfile.TemporaryDirectory() as directory:
            relay = self.make_relay(directory)
            callback = self.callback(relay)
            for rejected in (True, False):
                app = relay_module.AppServer("unused")
                with (
                    patch.object(relay, "_app_for_thread", return_value=app),
                    patch.object(app, "connect"),
                    patch.object(app, "initialize"),
                    patch.object(app, "resume_thread"),
                    patch.object(
                        app,
                        "queue_turn",
                        side_effect=relay_module.AppServerRejected("rejected")
                        if rejected
                        else None,
                        return_value={"queuedSubmission": {"id": "q"}},
                    ) as enqueue,
                    patch.object(app, "notifications", return_value=async_items([])),
                    self.assertLogs("test", level="ERROR")
                    if rejected
                    else patch.object(relay.log, "exception"),
                ):
                    await relay._handle_callback(FakeWebSocket(relay=relay), callback)
                    enqueue.assert_awaited_once()
                relay = self.make_relay(directory)
                self.assertEqual(
                    relay._submissions["message"]["state"], "failed" if rejected else "accepted"
                )
            with patch.object(relay, "_app_for_thread") as start:
                await relay._handle_callback(FakeWebSocket(relay=relay), callback)
                start.assert_not_called()

    async def test_lost_queue_ack_stays_unknown_and_never_retries(self):
        with tempfile.TemporaryDirectory() as directory:
            relay = self.make_relay(directory)
            callback = self.callback(relay)
            app = relay_module.AppServer("unused")
            ws = FakeWebSocket(relay=relay)

            async def queue(*_args):
                disk = json.loads(Path(relay.submissions_path).read_text())
                self.assertEqual(disk["message"]["state"], "submitting")
                raise TimeoutError("ack lost")

            with (
                patch.object(relay, "_app_for_thread", return_value=app),
                patch.object(app, "connect"),
                patch.object(app, "initialize"),
                patch.object(app, "resume_thread"),
                patch.object(app, "queue_turn", side_effect=queue),
                self.assertLogs("test", level="ERROR"),
            ):
                await relay._handle_callback(ws, callback)
            self.assertIn("提交结果未知", ws.messages[-1]["body"]["markdown"]["content"])
            restarted = self.make_relay(directory)
            with patch.object(restarted, "_app_for_thread") as start:
                await restarted._handle_callback(ws, callback)
                start.assert_not_called()
            self.assertEqual(restarted._submissions["message"]["state"], "unknown")

    async def test_progress_disconnect_preserves_acceptance(self):
        async def notifications():
            raise ConnectionError("lost progress")
            yield

        with tempfile.TemporaryDirectory() as directory:
            relay = self.make_relay(directory)
            callback = self.callback(relay)
            app = relay_module.AppServer("unused")
            ws = FakeWebSocket(relay=relay)
            with (
                patch.object(relay, "_app_for_thread", return_value=app),
                patch.object(app, "connect"),
                patch.object(app, "initialize"),
                patch.object(app, "resume_thread"),
                patch.object(app, "queue_turn", return_value={"queuedSubmission": {"id": "q"}}),
                patch.object(app, "notifications", side_effect=notifications),
                self.assertLogs("test", level="ERROR"),
            ):
                await relay._handle_callback(ws, callback)
            self.assertIn("已入队，进度连接断开", ws.messages[-1]["body"]["markdown"]["content"])
            restarted = self.make_relay(directory)
            self.assertEqual(restarted._submissions["message"]["submission_id"], "q")
            with patch.object(restarted, "_app_for_thread") as start:
                await restarted._handle_callback(ws, callback)
                start.assert_not_called()

    async def test_recovery_and_corrupt_ledger_fail_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "submissions.json"
            path.write_text(json.dumps({"A": {"state": "submitting"}, "B": {"state": "preparing"}}))
            relay = self.make_relay(directory)
            self.assertEqual(relay._submissions["A"]["state"], "unknown")
            self.assertEqual(relay._submissions["B"]["state"], "failed")
            path.write_text("broken")
            with self.assertRaises(ValueError):
                self.make_relay(directory)

    async def test_cancellation_preserves_submission_certainty(self):
        for accepted in (False, True):
            with self.subTest(accepted=accepted), tempfile.TemporaryDirectory() as directory:
                relay = self.make_relay(directory)
                callback = self.callback(relay)
                reached = asyncio.Event()
                app = relay_module.AppServer("unused")

                async def queue(*_args):
                    if not accepted:
                        reached.set()
                        await asyncio.Event().wait()
                    return {"queuedSubmission": {"id": "q"}}

                async def notifications():
                    reached.set()
                    await asyncio.Event().wait()
                    yield

                with (
                    patch.object(relay, "_app_for_thread", return_value=app),
                    patch.object(app, "connect"),
                    patch.object(app, "close") as close,
                    patch.object(app, "initialize"),
                    patch.object(app, "resume_thread"),
                    patch.object(app, "queue_turn", side_effect=queue),
                    patch.object(app, "notifications", side_effect=notifications),
                ):
                    running = asyncio.create_task(
                        relay._handle_callback(FakeWebSocket(relay=relay), callback)
                    )
                    await asyncio.wait_for(reached.wait(), 1)
                    running.cancel()
                    await asyncio.gather(running, return_exceptions=True)
                    close.assert_awaited_once()
                self.assertFalse(any(lock.locked() for lock in relay._submission_locks.values()))
                restarted = self.make_relay(directory)
                self.assertEqual(
                    restarted._submissions["message"]["state"],
                    "accepted" if accepted else "unknown",
                )

    async def test_quiet_suffix_flushes_without_waiting_for_next_delta(self):
        with tempfile.TemporaryDirectory() as directory:
            relay = self.make_relay(directory)
            callback = self.callback(relay)
            ws = FakeWebSocket(relay=relay)
            suffix_ready = asyncio.Event()
            finish = asyncio.Event()

            async def turn(*_args):
                yield ("queued", None)
                yield ("delta", "之后把实测发现与")
                await asyncio.sleep(0.005)
                yield ("delta", "设计建议分开汇报。")
                suffix_ready.set()
                await finish.wait()
                yield ("done", "completed")

            app = relay_module.AppServer("unused")
            with (
                patch.object(relay, "_app_for_thread", return_value=app),
                patch.object(app, "connect"),
                patch.object(app, "run_turn", side_effect=turn),
                patch.object(relay_module, "STREAM_FLUSH_INTERVAL", 0.04),
            ):
                running = asyncio.create_task(relay._handle_callback(ws, callback))
                try:
                    await asyncio.wait_for(suffix_ready.wait(), 1)
                    async with asyncio.timeout(1):
                        while (
                            "设计建议分开汇报。" not in ws.messages[-1]["body"]["stream"]["content"]
                        ):
                            await asyncio.sleep(0.005)
                    self.assertFalse(running.done())
                    self.assertFalse(ws.messages[-1]["body"]["stream"]["finish"])
                    sent = len(ws.messages)
                    await asyncio.sleep(0.12)
                    self.assertEqual(len(ws.messages), sent, "unchanged text was resent")
                finally:
                    finish.set()
                    await running

    async def test_message_boundary_flushes_immediately(self):
        with tempfile.TemporaryDirectory() as directory:
            relay = self.make_relay(directory)
            callback = self.callback(relay)
            ws = FakeWebSocket(relay=relay)
            finish = asyncio.Event()
            boundary = asyncio.Event()

            async def turn(*_args):
                yield ("queued", None)
                yield ("delta", "完整")
                yield ("delta", "句子。")
                yield ("boundary", None)
                boundary.set()
                await finish.wait()
                yield ("done", "completed")

            app = relay_module.AppServer("unused")
            with (
                patch.object(relay, "_app_for_thread", return_value=app),
                patch.object(app, "connect"),
                patch.object(app, "run_turn", side_effect=turn),
                patch.object(relay_module, "STREAM_FLUSH_INTERVAL", 60),
            ):
                running = asyncio.create_task(relay._handle_callback(ws, callback))
                try:
                    await asyncio.wait_for(boundary.wait(), 1)
                    self.assertIn("完整句子。", ws.messages[-1]["body"]["stream"]["content"])
                finally:
                    finish.set()
                    await running

    async def test_concurrent_turns_keep_independent_streams(self):
        with tempfile.TemporaryDirectory() as directory:
            relay = self.make_relay(directory)
            ws = FakeWebSocket(relay=relay)
            both_started = asyncio.Event()
            started = set()

            async def make_app(thread, _home):
                app = relay_module.AppServer("unused")
                app.connect = AsyncMock()

                async def turn(*_args):
                    yield ("queued", None)
                    started.add(thread)
                    if len(started) == 2:
                        both_started.set()
                    await both_started.wait()
                    yield ("delta", thread + " 的过")
                    yield ("delta", "程。\n\n")
                    yield ("boundary", None)
                    await asyncio.sleep(0)
                    yield ("delta", "\n")
                    yield ("delta", "\n" + thread + " 的结果。")
                    yield ("done", "completed")

                app.run_turn = Mock(side_effect=turn)
                return app

            with patch.object(relay, "_app_for_thread", side_effect=make_app):
                await asyncio.wait_for(
                    asyncio.gather(
                        relay._handle_callback(ws, self.callback(relay, "req-A", "A", 0)),
                        relay._handle_callback(ws, self.callback(relay, "req-B", "B", 1)),
                    ),
                    timeout=1,
                )
            stream_ids = {}
            for message in ws.messages:
                request_id = message["headers"]["req_id"]
                stream = message["body"]["stream"]
                own, other = ("A", "B") if request_id == "req-A" else ("B", "A")
                stream_ids.setdefault(own, set()).add(stream["id"])
                self.assertNotIn(other + " 的", stream["content"])
                if stream["finish"]:
                    self.assertIn(own + " 的过程。\n\n" + own + " 的结果。", stream["content"])
                    self.assertNotIn("\n\n\n", stream["content"])
            self.assertEqual(len(stream_ids["A"]), 1)
            self.assertEqual(len(stream_ids["B"]), 1)
            self.assertTrue(stream_ids["A"].isdisjoint(stream_ids["B"]))

    def make_relay(self, directory):
        return relay_module.Relay(
            {"bot_id": "bot", "secret": "secret"},
            "wss://example.invalid",
            directory,
            logging.getLogger("test"),
            [str(Path(directory) / "official"), str(Path(directory) / "tca")],
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
            server = await unix_serve(serve, path)
            async with server:
                app = relay_module.AppServer(path)
                await app.connect()
                try:
                    result = await asyncio.wait_for(self.collect_turn(app), timeout=2)
                finally:
                    await app.close()
        self.assertEqual(result, [("queued", None), ("delta", "answer"), ("done", "completed")])

    async def collect_turn(self, app):
        return [item async for item in app.run_turn("thread", "reply")]

    async def test_mock_turn_stream_and_completion_push_are_complementary(self):
        async def serve(websocket):
            async for raw in websocket:
                request = json.loads(raw)
                if "id" not in request:
                    continue
                result = {}
                if request["method"] == "thread/queue/add":
                    result = {"queuedSubmission": {"id": "queued-id"}}
                await websocket.send(json.dumps({"id": request["id"], "result": result}))
                if request["method"] == "thread/queue/add":
                    client_id = request["params"]["clientUserMessageId"]
                    for method, params in [
                        ("item/started", {"item": {"type": "userMessage", "clientId": client_id}}),
                        ("item/agentMessage/delta", {"delta": "检查配置。"}),
                        ("item/completed", {"item": {"type": "agentMessage"}}),
                        ("item/commandExecution/outputDelta", {"delta": "TOOL STDOUT"}),
                        ("item/agentMessage/delta", {"delta": "修复完成。"}),
                        ("turn/completed", {"turn": {"id": "reply-turn", "status": "completed"}}),
                    ]:
                        await websocket.send(
                            json.dumps(
                                {"method": method, "params": {"turnId": "reply-turn", **params}}
                            )
                        )

        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / "app.sock")
            server = await unix_serve(serve, path)
            async with server:
                relay = self.make_relay(directory)
                websocket = FakeWebSocket(relay=relay)
                with patch.object(
                    relay, "_app_for_thread", return_value=relay_module.AppServer(path)
                ):
                    running = asyncio.create_task(
                        relay._run_turn(
                            websocket,
                            {"headers": {"req_id": "reply"}, "body": {"from": {"userid": "user"}}},
                            "thread",
                            "继续",
                            relay.codex_homes[0],
                        )
                    )
                    async with asyncio.timeout(3):
                        while not relay._completion_waiters:
                            await asyncio.sleep(0)
                self.assertFalse(running.done())

                Path(relay.outbox).write_text(
                    json.dumps(
                        {
                            "thread": "thread",
                            "turn": "reply-turn",
                            "codex_home": str(relay.codex_homes[0]),
                            "chatid": "user",
                            "content": "修复完成。",
                        }
                    )
                    + "\n"
                )
                delivery = asyncio.create_task(relay._process_outbox(websocket))
                async with asyncio.timeout(2):
                    while websocket.messages[-1]["cmd"] != "aibot_send_msg":
                        await asyncio.sleep(0)
                notification = websocket.messages[-1]
                self.assertFalse(running.done(), "stream trimmed before completion ACK")
                relay._resolve_command({"headers": notification["headers"], "errcode": 0})
                await asyncio.wait_for(delivery, timeout=2)
                await asyncio.wait_for(running, timeout=2)
                streams = [
                    message["body"]["stream"]
                    for message in websocket.messages
                    if message["body"].get("msgtype") == "stream"
                ]
                self.assertFalse(streams[0]["finish"])
                self.assertTrue(streams[-1]["finish"])
                self.assertIn("检查配置。", streams[-1]["content"])
                self.assertNotIn("修复完成。", streams[-1]["content"])
                self.assertNotIn("TOOL STDOUT", streams[-1]["content"])
                content = notification["body"]["markdown"]["content"]
                self.assertIn("修复完成。", content)
                self.assertNotIn("检查配置。", content)
                self.assertIn("回复本条消息继续", content)
                self.assertFalse(any(lock.locked() for lock in relay._submission_locks.values()))

    async def test_long_completion_resumes_after_last_ack_and_receipt_survives_restart(self):
        with tempfile.TemporaryDirectory() as directory:
            relay = self.make_relay(directory)
            home = str(relay.codex_homes[0])
            text = '甲😀"\\正文' * 100
            Path(relay.outbox).write_text(
                json.dumps(
                    {
                        "thread": "thread",
                        "turn": "turn",
                        "codex_home": home,
                        "chatid": "user",
                        "content": text,
                    }
                )
                + "\n"
            )
            delivered = []
            attempts = 0

            async def reject_second(_ws, _cmd, body, **_kwargs):
                nonlocal attempts
                attempts += 1
                if attempts == 2:
                    return {"errcode": 1}
                delivered.append(body["markdown"]["content"])
                return {"errcode": 0}

            with (
                patch.object(relay_module, "MAX_CONTENT_BYTES", 256),
                patch.object(relay, "_send", side_effect=reject_second),
            ):
                with self.assertRaises(RuntimeError):
                    await relay._process_outbox(FakeWebSocket(relay=relay))
            key = relay._completion_key(home, "thread", "turn", "user")
            self.assertNotIn(key, relay._delivered)
            restarted = self.make_relay(directory)

            async def accept(_ws, _cmd, body, **_kwargs):
                delivered.append(body["markdown"]["content"])
                return {"errcode": 0}

            with (
                patch.object(relay_module, "MAX_CONTENT_BYTES", 256),
                patch.object(restarted, "_send", side_effect=accept),
            ):
                await restarted._process_outbox(FakeWebSocket())
            bodies = []
            for content in delivered:
                self.assertLessEqual(len(content.encode("utf-8")), 256)
                body = content.removeprefix("**Codex 完成**\n\n").split("\n\n回复本条消息继续：")[0]
                bodies.append(body)
            self.assertEqual("".join(bodies), text)
            self.assertGreater(len(bodies), 2)
            self.assertFalse(Path(relay.outbox + ".processing").exists())
            after_restart = self.make_relay(directory)
            self.assertTrue(
                await after_restart._completion_confirmed(home, "thread", "turn", "user")
            )
            with patch.object(relay_module, "COMPLETION_WAIT_TIMEOUT", 0.005):
                for values in [
                    (str(relay.codex_homes[1]), "thread", "turn", "user"),
                    (home, "other-thread", "turn", "user"),
                    (home, "thread", "other-turn", "user"),
                    (home, "thread", "turn", "other-user"),
                ]:
                    self.assertFalse(await after_restart._completion_confirmed(*values))

    async def test_missing_completion_notification_retains_final_answer(self):
        with tempfile.TemporaryDirectory() as directory:
            relay = self.make_relay(directory)
            callback = self.callback(relay)
            app = relay_module.AppServer("unused")
            app.turn_id = "turn-without-notification"
            ws = FakeWebSocket(relay=relay)
            with (
                patch.object(relay, "_app_for_thread", return_value=app),
                patch.object(app, "connect"),
                patch.object(
                    app,
                    "run_turn",
                    return_value=async_items(
                        [("queued", None), ("delta", "最终答案不能丢"), ("done", "completed")]
                    ),
                ),
                patch.object(relay_module, "COMPLETION_WAIT_TIMEOUT", 0.01),
            ):
                await relay._handle_callback(ws, callback)
            self.assertTrue(ws.messages[-1]["body"]["stream"]["finish"])
            self.assertIn("最终答案不能丢", ws.messages[-1]["body"]["stream"]["content"])

    async def test_stream_rejected_ack_is_not_silently_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            relay = self.make_relay(directory)
            ws = FakeWebSocket()

            async def send(_ws, _cmd, _body, **_kwargs):
                return {"errcode": 1}

            with patch.object(relay, "_send", side_effect=send):
                with self.assertRaises(RuntimeError):
                    await relay._stream(
                        ws, {"headers": {"req_id": "request"}}, "stream", "内容", False
                    )

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
                    relay._run_turn(
                        FakeWebSocket(relay=relay), {}, "thread", "reply", relay.codex_homes[0]
                    )
                )
                try:
                    await asyncio.wait_for(started.wait(), timeout=1)
                    self.assertFalse(
                        any(lock.locked() for lock in relay._submission_locks.values())
                    )
                finally:
                    running.cancel()
                    await asyncio.gather(running, return_exceptions=True)
                close.assert_awaited_once_with()
                self.assertFalse(any(lock.locked() for lock in relay._submission_locks.values()))

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
            websocket = FakeWebSocket(relay=relay)

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
            websocket = FakeWebSocket(relay=relay)

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
            websocket = FakeWebSocket(relay=relay)
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

    def make_database(self, home, thread_id):
        home.mkdir(parents=True, exist_ok=True)
        connection = sqlite3.connect(home / "state_5.sqlite")
        try:
            connection.execute("CREATE TABLE threads (id TEXT PRIMARY KEY)")
            connection.execute("INSERT INTO threads VALUES (?)", (thread_id,))
            connection.commit()
        finally:
            connection.close()

    def fake_daemon(self, socket_path):
        process = Mock(returncode=0)
        process.communicate = AsyncMock(
            return_value=(json.dumps({"socketPath": socket_path}).encode(), b"")
        )
        process.wait = AsyncMock()
        return process

    async def test_hook_home_starts_only_its_daemon_without_database_lookup(self):
        with tempfile.TemporaryDirectory() as directory:
            relay = self.make_relay(directory)
            for home in relay.codex_homes:
                with (
                    self.subTest(home=home),
                    patch.object(
                        relay, "_home_for_thread", side_effect=AssertionError("unexpected lookup")
                    ),
                    patch.object(
                        relay_module.asyncio,
                        "create_subprocess_exec",
                        return_value=self.fake_daemon("/tmp/chosen.sock"),
                    ) as start,
                ):
                    app = await relay._app_for_thread("thread", str(home))
                    self.assertEqual(app.path, "/tmp/chosen.sock")
                    self.assertEqual(
                        start.call_args.args, ("codex", "app-server", "daemon", "start")
                    )
                    self.assertEqual(start.call_args.kwargs["env"]["CODEX_HOME"], str(home))
                    self.assertEqual(start.call_args.kwargs["cwd"], home)

    async def test_old_token_finds_tca_session_when_official_daemon_is_absent(self):
        with tempfile.TemporaryDirectory() as directory:
            relay = self.make_relay(directory)
            self.make_database(relay.codex_homes[1], "thread")
            with patch.object(
                relay_module.asyncio,
                "create_subprocess_exec",
                return_value=self.fake_daemon("/tmp/tca.sock"),
            ) as start:
                app = await relay._app_for_thread("thread")
            self.assertEqual(app.path, "/tmp/tca.sock")
            self.assertEqual(start.call_args.kwargs["env"]["CODEX_HOME"], str(relay.codex_homes[1]))
            self.assertFalse((relay.codex_homes[0] / "state_5.sqlite").exists())

    async def test_old_token_refuses_missing_or_duplicate_thread(self):
        with tempfile.TemporaryDirectory() as directory:
            relay = self.make_relay(directory)
            with patch.object(relay_module.asyncio, "create_subprocess_exec") as start:
                with self.assertRaisesRegex(relay_module.AppServerError, "not found"):
                    await relay._app_for_thread("missing")
                for home in relay.codex_homes:
                    self.make_database(home, "thread")
                with self.assertRaisesRegex(relay_module.AppServerError, "multiple"):
                    await relay._app_for_thread("thread")
                start.assert_not_called()

    async def test_reply_token_preserves_home_across_relay_restart(self):
        with tempfile.TemporaryDirectory() as directory:
            relay = self.make_relay(directory)
            home = str(relay.codex_homes[1])
            token = relay._new_token("thread", home)
            restarted = self.make_relay(directory)
            callback = {
                "body": {
                    "msgtype": "text",
                    "text": {"content": "reply"},
                    "quote": {"text": {"content": f"r#{token}"}},
                }
            }
            with patch.object(restarted, "_run_turn") as run:
                ws = FakeWebSocket(relay=relay)
                await restarted._handle_callback(ws, callback)
                run.assert_awaited_once_with(ws, callback, "thread", "reply", home)

    async def test_outbox_home_is_bound_to_token(self):
        with tempfile.TemporaryDirectory() as directory:
            relay = self.make_relay(directory)
            home = str(relay.codex_homes[1])
            Path(relay.outbox).write_text(
                json.dumps(
                    {"thread": "thread", "chatid": "user", "content": "done", "codex_home": home}
                )
                + "\n"
            )
            with patch.object(relay, "_send", return_value={"errcode": 0}):
                await relay._process_outbox(FakeWebSocket(relay=relay))
            token = relay._last_push["user"]["token"]
            self.assertEqual(relay._tokens[token]["codex_home"], home)

    async def test_unconfigured_hook_home_never_starts_daemon(self):
        with tempfile.TemporaryDirectory() as directory:
            relay = self.make_relay(directory)
            with patch.object(relay_module.asyncio, "create_subprocess_exec") as start:
                with self.assertRaisesRegex(relay_module.AppServerError, "unconfigured"):
                    await relay._app_for_thread("thread", "/tmp/unconfigured")
                start.assert_not_called()

    async def test_legacy_official_token_follows_home_migration(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            old = root / ".codex"
            new = root / ".codex-openai"
            new.mkdir()
            relay = relay_module.Relay(
                {"bot_id": "bot", "secret": "secret"},
                "wss://example.invalid",
                directory,
                logging.getLogger("test"),
                [new],
            )
            self.assertEqual(relay._configured_home(str(old)), new)
            old.mkdir()
            with self.assertRaisesRegex(relay_module.AppServerError, "unconfigured"):
                relay._configured_home(str(old))

    async def test_failed_daemon_start_reports_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            relay = self.make_relay(directory)
            process = self.fake_daemon("unused")
            process.returncode = 1
            with patch.object(relay_module.asyncio, "create_subprocess_exec", return_value=process):
                with self.assertRaisesRegex(relay_module.AppServerError, "could not start"):
                    await relay._app_for_thread("thread", str(relay.codex_homes[0]))

    async def test_cancellation_stops_daemon_start_process(self):
        with tempfile.TemporaryDirectory() as directory:
            relay = self.make_relay(directory)
            started = asyncio.Event()
            process = self.fake_daemon("unused")
            process.returncode = None

            async def communicate():
                started.set()
                await asyncio.Event().wait()

            process.communicate.side_effect = communicate
            with patch.object(relay_module.asyncio, "create_subprocess_exec", return_value=process):
                running = asyncio.create_task(
                    relay._app_for_thread("thread", str(relay.codex_homes[0]))
                )
                await asyncio.wait_for(started.wait(), timeout=1)
                running.cancel()
                with self.assertRaises(asyncio.CancelledError):
                    await running
            process.kill.assert_called_once()
            process.wait.assert_awaited_once()


if __name__ == "__main__":
    unittest.main()
