"""WeCom smart-bot long-connection transport wired to a local Codex app-server.

It speaks the WeCom smart-bot WebSocket protocol (official doc
path/101463): subscribe with BotID/Secret, keep the connection alive with
application-level ping, receive `aibot_msg_callback`, and answer via
`aibot_respond_msg`.

Two loops feed it:

- codex-notify appends one JSON line per completed turn to
  $XDG_STATE_HOME/codex-wecom-relay/outbox.jsonl. Each line already carries the
  target chatid resolved by the thread's route; this process only delivers.
  The message is pushed to WeCom as markdown embedding a short `r#xxxxxxxx`
  token, and token -> thread is recorded in tokens.json.
- When the user quotes that message and replies, the callback's quote field
  carries the token; it resolves the token to the thread, queues the reply
  through the local app-server (`thread/queue/add`), and streams that turn's
  agent text back as a WeCom stream message.

The app-server control sockets are passed explicitly with `--default-socket`
and optional `--provider-socket` flags. They speak WebSocket over Unix sockets;
both those connections and the WeCom connection use the `websockets` library.

Credentials (bot_id, secret) live in
$XDG_CONFIG_HOME/codex-wecom-relay/wecom.json, materialized by sops-nix. Logs
go to stderr for journald; credentials, tokens and message content are never
logged.
"""

import argparse
import asyncio
import hashlib
import json
import logging
import os
import queue
import re
import secrets
import sys
import threading
import time
from collections import deque
from pathlib import Path

from websockets.asyncio.client import connect
from websockets.sync.client import unix_connect

WSS_URL = "wss://openws.work.weixin.qq.com"
PING_INTERVAL = 30
TOKEN_RE = re.compile(r"r#([0-9a-f]{8})")
STREAM_FLUSH_INTERVAL = 0.8
MAX_STREAM_CHARS = 20000
TOKEN_TTL_SECONDS = 7 * 86400
COMMAND_ACK_TIMEOUT = 15


def load_json(path, default):
    try:
        with open(path, encoding="utf-8") as handle:
            value = json.load(handle)
        return value if isinstance(value, type(default)) else default
    except (OSError, json.JSONDecodeError):
        return default


def save_json(path, value):
    """Atomically replace a JSON state file."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value), encoding="utf-8")
    temporary.replace(path)


class AppServerError(Exception):
    pass


class AppServer:
    """Blocking JSON-RPC client for `codex app-server` over WebSocket."""

    def __init__(self, path):
        self.path = path
        self._socket = None
        self._next_id = 0
        self._pending_notifications = deque()

    def connect(self):
        self._socket = unix_connect(
            self.path, open_timeout=30, ping_interval=None, compression=None
        )

    def close(self):
        if self._socket is not None:
            self._socket.close()
            self._socket = None

    def _send_json(self, message):
        self._socket.send(json.dumps(message))

    def _receive_json(self):
        message = self._socket.recv()
        if not isinstance(message, str):
            raise AppServerError("app-server returned a binary WebSocket message")
        return json.loads(message)

    def _next_request_id(self):
        self._next_id += 1
        return self._next_id

    def request(self, method, params=None):
        request_id = self._next_request_id()
        self._send_json({"method": method, "id": request_id, "params": params or {}})
        while True:
            message = self._receive_json()
            if message.get("id") != request_id:
                if "method" in message:
                    self._pending_notifications.append(message)
                continue
            if "error" in message:
                raise AppServerError(f"{method} failed: {message['error']}")
            return message.get("result")

    def notifications(self):
        while True:
            message = (
                self._pending_notifications.popleft()
                if self._pending_notifications
                else self._receive_json()
            )
            if "method" in message:
                yield message

    def initialize(self, client_name="codex-wecom-relay"):
        self.request(
            "initialize",
            {
                "clientInfo": {
                    "name": client_name,
                    "title": "codex-wecom-relay",
                    "version": "0.1",
                },
                "capabilities": {"experimentalApi": True},
            },
        )
        self._send_json({"method": "initialized", "params": {}})

    def resume_thread(self, thread_id):
        return self.request("thread/resume", {"threadId": thread_id})

    def read_thread(self, thread_id):
        return self.request("thread/read", {"threadId": thread_id, "includeTurns": False})

    def queue_turn(self, thread_id, text, client_message_id):
        # TUI Tab follow-ups live in the TUI, outside this server queue. If
        # both clients submit at the same idle boundary, the TUI's turn/start
        # can steer into a turn started from this queue. See README.md.
        return self.request(
            "thread/queue/add",
            {
                "threadId": thread_id,
                "input": [{"type": "text", "text": text}],
                "clientUserMessageId": client_message_id,
            },
        )

    def run_turn(self, thread_id, text):
        """Queue a turn and stream the response tied to its user message."""
        self.initialize()
        # A connection must subscribe to the thread even when another client
        # already loaded it. Otherwise queue/add can succeed while this
        # connection receives none of the turn's notifications.
        self.resume_thread(thread_id)
        client_message_id = secrets.token_hex(16)
        queued = self.queue_turn(thread_id, text, client_message_id) or {}
        if not (queued.get("queuedSubmission") or {}).get("id"):
            raise AppServerError("thread/queue/add returned no queued submission ID")
        yield ("queued", None)
        turn_id = None
        for notification in self.notifications():
            method = notification.get("method")
            params = notification.get("params", {})
            if (
                method == "item/started"
                and (params.get("item") or {}).get("type") == "userMessage"
                and (params.get("item") or {}).get("clientId") == client_message_id
            ):
                turn_id = params.get("turnId")
                continue
            notification_turn_id = params.get("turnId") or (params.get("turn") or {}).get("id")
            if turn_id is None or notification_turn_id != turn_id:
                continue
            if method == "item/agentMessage/delta":
                yield ("delta", params.get("delta", ""))
            elif method == "turn/completed":
                status = params.get("status") or params.get("turn", {}).get("status")
                yield ("done", status)
                return


def _turn_producer(app, thread_id, text, result_queue):
    """Run the blocking app-server turn in a worker thread."""
    try:
        for item in app.run_turn(thread_id, text):
            result_queue.put(item)
    except Exception as exc:  # forwarded to the event loop
        result_queue.put(("error", exc))


def load_config(path):
    with open(path, encoding="utf-8") as handle:
        config = json.load(handle)
    bot_id = config.get("bot_id")
    secret = config.get("secret")
    if not bot_id or not secret:
        raise ValueError("config must define bot_id and secret")
    return {
        "bot_id": bot_id,
        "secret": secret,
    }


class Relay:
    def __init__(self, config, ws_url, state_dir, log, default_socket, provider_sockets=None):
        self.bot_id = config["bot_id"]
        self.secret = config["secret"]
        self.ws_url = ws_url
        self.state_dir = state_dir
        self.outbox = os.path.join(state_dir, "outbox.jsonl")
        self.tokens_path = os.path.join(state_dir, "tokens.json")
        self.last_push_path = os.path.join(state_dir, "last-push.json")
        self.log = log
        self.default_socket = default_socket
        self.provider_sockets = provider_sockets or {}
        self._seq = 0
        self._seen = deque(maxlen=1000)
        self._tokens = {}
        self._last_push = {}
        self._pending_commands = {}
        # Preserve WeCom callback order while each app-server connection
        # performs provider lookup and queue/add. Streaming may then overlap.
        self._submission_lock = asyncio.Lock()
        self._load_tokens()
        self._load_last_push()

    def _load_tokens(self):
        data = load_json(self.tokens_path, {})
        cutoff = time.time() - TOKEN_TTL_SECONDS
        self._tokens = {
            token: entry
            for token, entry in data.items()
            if isinstance(entry, dict) and entry.get("created", 0) > cutoff
        }

    def _save_tokens(self):
        save_json(self.tokens_path, self._tokens)

    def _load_last_push(self):
        data = load_json(self.last_push_path, {})
        self._last_push = {
            chatid: entry
            for chatid, entry in data.items()
            if isinstance(entry, dict) and entry.get("token") in self._tokens
        }

    def _save_last_push(self):
        save_json(self.last_push_path, self._last_push)

    def _req_id(self):
        self._seq += 1
        return f"codex-wecom-relay-{os.getpid()}-{time.time_ns()}-{self._seq}"

    async def _send(self, ws, cmd, body=None, req_id=None, wait_for_ack=False):
        payload = {
            "cmd": cmd,
            "headers": {"req_id": req_id or self._req_id()},
            "body": body or {},
        }
        request_id = payload["headers"]["req_id"]
        response = None
        if wait_for_ack:
            response = asyncio.get_running_loop().create_future()
            self._pending_commands[request_id] = response
        try:
            await ws.send(json.dumps(payload))
            if response is None:
                return request_id
            return await asyncio.wait_for(response, timeout=COMMAND_ACK_TIMEOUT)
        finally:
            self._pending_commands.pop(request_id, None)

    def _resolve_command(self, message):
        request_id = message.get("headers", {}).get("req_id")
        pending = self._pending_commands.get(request_id)
        if pending is None or pending.done():
            return False
        pending.set_result(message)
        return True

    async def _respond(self, ws, callback, body):
        req_id = callback.get("headers", {}).get("req_id", "")
        await ws.send(
            json.dumps(
                {
                    "cmd": "aibot_respond_msg",
                    "headers": {"req_id": req_id},
                    "body": body,
                }
            )
        )

    async def _respond_markdown(self, ws, callback, content):
        await self._respond(ws, callback, {"msgtype": "markdown", "markdown": {"content": content}})

    async def _stream(self, ws, callback, stream_id, content, finish):
        await self._respond(
            ws,
            callback,
            {
                "msgtype": "stream",
                "stream": {"id": stream_id, "finish": finish, "content": content},
            },
        )

    def _new_token(self, thread_id):
        while True:
            token = secrets.token_hex(4)
            if token not in self._tokens:
                break
        self._tokens[token] = {"thread": thread_id, "created": int(time.time())}
        self._save_tokens()
        return token

    async def _process_outbox(self, ws):
        tmp = self.outbox + ".processing"
        if not os.path.exists(tmp):
            try:
                os.replace(self.outbox, tmp)
            except FileNotFoundError:
                return
        with open(tmp, encoding="utf-8") as handle:
            lines = handle.readlines()
        while lines:
            raw = lines[0]
            try:
                entry = json.loads(raw)
            except json.JSONDecodeError:
                self.log.warning("outbox entry skipped: invalid JSON")
                lines.pop(0)
                self._checkpoint_outbox(tmp, lines)
                continue
            thread_id = entry.get("thread") or ""
            target = entry.get("chatid") or ""
            # The body keeps the assistant's own line structure: WeCom
            # markdown renders it, and flattening here would undo the
            # formatting the notify side preserved.
            body = (entry.get("content") or "").strip()
            if not thread_id or not target:
                self.log.warning("outbox entry skipped: missing thread or chatid")
                lines.pop(0)
                self._checkpoint_outbox(tmp, lines)
                continue
            token = entry.get("token") or ""
            token_entry = self._tokens.get(token)
            if token_entry is None or token_entry.get("thread") != thread_id:
                token = self._new_token(thread_id)
                entry["token"] = token
                lines[0] = json.dumps(entry) + "\n"
                self._checkpoint_outbox(tmp, lines)
            content = "\n\n".join(
                section
                for section in [
                    "**Codex 完成**",
                    body,
                    f"回复本条消息继续：`r#{token}`",
                ]
                if section
            )
            response = await self._send(
                ws,
                "aibot_send_msg",
                {
                    "chatid": target,
                    "chat_type": 1,
                    "msgtype": "markdown",
                    "markdown": {"content": content},
                },
                wait_for_ack=True,
            )
            if response.get("errcode") != 0:
                raise RuntimeError(
                    f"aibot_send_msg rejected: errcode={response.get('errcode')} "
                    f"errmsg={response.get('errmsg')}"
                )
            self.log.info("pushed thread=%s token=r#%s", thread_id, token)
            self._last_push[target] = {
                "token": token,
                "thread": thread_id,
                "at": int(time.time()),
            }
            self._save_last_push()
            lines.pop(0)
            self._checkpoint_outbox(tmp, lines)

    @staticmethod
    def _checkpoint_outbox(path, lines):
        """Commit delivered lines while keeping the remainder retryable."""
        if not lines:
            os.unlink(path)
            return
        temporary = path + ".tmp"
        with open(temporary, "w", encoding="utf-8") as handle:
            handle.writelines(lines)
        os.replace(temporary, path)

    async def _outbox_loop(self, ws):
        delay = 1
        while True:
            await asyncio.sleep(delay)
            try:
                await self._process_outbox(ws)
            except Exception:
                self.log.exception("outbox processing failed")
                delay = min(delay * 2, 60)
            else:
                delay = 1

    def _extract_reply(self, body):
        text = (body.get("text") or {}).get("content", "")
        quote = body.get("quote") or {}
        quoted = (quote.get("text") or {}).get("content", "")
        match = TOKEN_RE.search(quoted) or TOKEN_RE.search(text)
        if match:
            return match.group(1), re.sub(r"^\s*@\S+\s*", "", text)
        return None, text

    def _stream_id(self, callback):
        req_id = callback.get("headers", {}).get("req_id", self._req_id())
        digest = hashlib.sha256(req_id.encode()).hexdigest()[:12]
        return f"s{digest}"

    def _app_for_thread(self, thread_id):
        if not self.provider_sockets:
            return AppServer(self.default_socket)
        metadata = AppServer(self.default_socket)
        try:
            metadata.connect()
            metadata.initialize("codex-wecom-relay-router")
            result = metadata.read_thread(thread_id) or {}
            provider = (result.get("thread") or {}).get("modelProvider")
        finally:
            metadata.close()
        return AppServer(self.provider_sockets.get(provider, self.default_socket))

    async def _run_turn(self, ws, callback, thread_id, text):
        stream_id = self._stream_id(callback)
        await self._submission_lock.acquire()
        submission_locked = True
        app = None
        parts = []
        last_flush = 0.0
        status = None
        result_queue = queue.Queue()
        try:
            app = await asyncio.to_thread(self._app_for_thread, thread_id)
            await asyncio.to_thread(app.connect)
            producer = threading.Thread(
                target=_turn_producer,
                args=(app, thread_id, text, result_queue),
                daemon=True,
            )
            producer.start()
            while True:
                try:
                    kind, value = result_queue.get_nowait()
                except queue.Empty:
                    if not producer.is_alive() and result_queue.empty():
                        break
                    await asyncio.sleep(0.05)
                    continue
                if kind == "delta":
                    parts.append(value)
                    now = time.monotonic()
                    if now - last_flush >= STREAM_FLUSH_INTERVAL:
                        last_flush = now
                        await self._stream(
                            ws, callback, stream_id, "".join(parts)[-MAX_STREAM_CHARS:], False
                        )
                elif kind == "queued":
                    await self._stream(ws, callback, stream_id, "已排队，等待当前任务完成。", False)
                    self._submission_lock.release()
                    submission_locked = False
                elif kind == "done":
                    status = value
                else:  # error
                    raise value
            final = "".join(parts).strip()
            if not final:
                final = f"(本轮完成，status={status})"
            await self._stream(ws, callback, stream_id, final[-MAX_STREAM_CHARS:], True)
        except (AppServerError, ConnectionError, OSError) as exc:
            self.log.warning("turn failed thread=%s: %s", thread_id, exc)
            await self._respond_markdown(ws, callback, f"Codex 注入失败：{exc}")
        except Exception:
            self.log.exception("turn failed thread=%s", thread_id)
            await self._respond_markdown(ws, callback, "Codex 注入失败：内部错误")
        finally:
            if submission_locked:
                self._submission_lock.release()
            if app is not None:
                app.close()

    async def _handle_callback(self, ws, callback):
        body = callback.get("body", {})
        self.log.debug("callback: %s", json.dumps(callback, ensure_ascii=False))
        msgid = body.get("msgid")
        if msgid:
            if msgid in self._seen:
                return
            self._seen.append(msgid)
        if body.get("msgtype") != "text":
            self.log.info("ignoring non-text message msgtype=%s", body.get("msgtype"))
            return
        token, text = self._extract_reply(body)
        if not token:
            # No quote and no token in the text: continue the most recent
            # conversation the relay pushed to this sender.
            userid = (body.get("from") or {}).get("userid", "")
            entry = self._last_push.get(userid)
            if entry:
                token = entry["token"]
                self.log.info("reply fallback: last push for chatid=%s", userid)
        if token and token in self._tokens:
            thread_id = self._tokens[token]["thread"]
            self.log.info("reply token=r#%s thread=%s", token, thread_id)
            await self._run_turn(ws, callback, thread_id, text)
        else:
            await self._respond_markdown(
                ws,
                callback,
                "没有找到对应任务：请先让 Codex 完成一轮，或引用某条完成通知再回复。",
            )

    async def _run_once(self):
        # proxy=None: connect directly; the WeCom endpoint is domestic and
        # must not be routed through the user's overseas SOCKS proxy
        # (websockets otherwise honors ALL_PROXY/https_proxy).
        # ping_interval=None: WeCom's keepalive is the application-level
        # `cmd: ping` we send every 30s; the library's protocol-level pings
        # are rejected (1002). compression=None: WeCom sends frames with
        # reserved bits that break permessage-deflate negotiation.
        async with connect(self.ws_url, proxy=None, ping_interval=None, compression=None) as ws:
            self.log.info("connected to %s", self.ws_url)
            await self._send(
                ws,
                "aibot_subscribe",
                {"bot_id": self.bot_id, "secret": self.secret},
            )
            subscribed = False
            last_activity = [time.monotonic()]
            callback_queue = asyncio.Queue()
            callback_tasks = set()

            async def receive():
                nonlocal subscribed
                async for raw in ws:
                    last_activity[0] = time.monotonic()
                    message = json.loads(raw)
                    cmd = message.get("cmd")
                    if cmd == "aibot_msg_callback":
                        await callback_queue.put(message)
                    elif cmd == "aibot_event_callback":
                        event = message.get("body", {}).get("event", {}).get("eventtype")
                        self.log.info("event=%s", event)
                        if event == "disconnected_event":
                            raise ConnectionError("connection superseded by another client")
                    else:
                        self._resolve_command(message)
                        errcode = message.get("errcode")
                        if errcode not in (None, 0):
                            if not subscribed:
                                raise RuntimeError(
                                    f"subscribe rejected: errcode={errcode} errmsg={message.get('errmsg')}"
                                )
                            self.log.warning(
                                "command failed cmd=%s errcode=%s errmsg=%s",
                                cmd,
                                errcode,
                                message.get("errmsg"),
                            )
                        elif not subscribed:
                            subscribed = True
                            self.log.info("subscribed bot_id=%s", self.bot_id)
                raise ConnectionError("connection closed")

            async def handle_callbacks():
                async def handle_one(callback):
                    try:
                        await self._handle_callback(ws, callback)
                    except Exception:
                        self.log.exception("callback processing failed")
                    finally:
                        callback_queue.task_done()

                while True:
                    callback = await callback_queue.get()
                    task = asyncio.create_task(handle_one(callback))
                    callback_tasks.add(task)
                    task.add_done_callback(callback_tasks.discard)

            async def heartbeat():
                while True:
                    await asyncio.sleep(PING_INTERVAL)
                    await self._send(ws, "ping")

            async def watchdog():
                while True:
                    await asyncio.sleep(30)
                    if time.monotonic() - last_activity[0] > 90:
                        raise ConnectionError("no server activity for 90s")

            tasks = [
                asyncio.create_task(receive()),
                asyncio.create_task(handle_callbacks()),
                asyncio.create_task(heartbeat()),
                asyncio.create_task(self._outbox_loop(ws)),
                asyncio.create_task(watchdog()),
            ]
            try:
                done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_EXCEPTION)
                for task in done:
                    error = task.exception()
                    if error is not None:
                        raise error
            finally:
                for task in tasks:
                    task.cancel()
                for task in callback_tasks:
                    task.cancel()
                await asyncio.gather(*tasks, return_exceptions=True)
                await asyncio.gather(*callback_tasks, return_exceptions=True)
                for pending in self._pending_commands.values():
                    if not pending.done():
                        pending.cancel()
                self._pending_commands.clear()

    async def run(self):
        backoff = 1
        while True:
            try:
                await self._run_once()
            except (ConnectionError, OSError, asyncio.TimeoutError) as exc:
                self.log.warning("connection lost (%s); retrying in %ss", exc, backoff)
                await asyncio.sleep(backoff)
                backoff = min(backoff * 2, 60)
            except RuntimeError as exc:
                self.log.error("%s; giving up", exc)
                return 1
            except Exception:
                self.log.exception("unexpected error; retrying in 10s")
                await asyncio.sleep(10)
            else:
                self.log.info("connection closed; reconnecting in %ss", backoff)
                await asyncio.sleep(backoff)
                backoff = 1


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    default_config = os.path.join(
        os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")),
        "codex-wecom-relay",
        "wecom.json",
    )
    parser.add_argument(
        "--config",
        default=os.environ.get("WECOM_CONFIG") or default_config,
        help="JSON file with bot_id and secret",
    )
    parser.add_argument("--ws-url", default=WSS_URL)
    parser.add_argument(
        "--state-dir",
        default=os.path.join(
            os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
            "codex-wecom-relay",
        ),
    )
    parser.add_argument("--log-level", default="INFO")
    parser.add_argument(
        "--default-socket",
        required=True,
        metavar="PATH",
        help="app-server Unix socket for the default model provider and thread metadata",
    )
    parser.add_argument(
        "--provider-socket",
        action="append",
        default=[],
        metavar="PROVIDER=PATH",
        help="route threads from PROVIDER to a dedicated app-server Unix socket",
    )
    args = parser.parse_args(argv)

    try:
        provider_sockets = dict(item.split("=", 1) for item in args.provider_socket)
    except ValueError:
        parser.error("--provider-socket must be PROVIDER=PATH")

    logging.basicConfig(
        level=args.log_level,
        format="[%(asctime)s] %(levelname)s %(name)s %(message)s",
        stream=sys.stderr,
    )
    log = logging.getLogger("codex-wecom-relay")

    if not os.path.exists(args.config):
        log.error("config %s not found; create it with bot_id and secret", args.config)
        return 0
    try:
        config = load_config(args.config)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        log.error("cannot load config: %s", exc)
        return 1

    relay = Relay(config, args.ws_url, args.state_dir, log, args.default_socket, provider_sockets)
    try:
        return asyncio.run(relay.run())
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    sys.exit(main())
