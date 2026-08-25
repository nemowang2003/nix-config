"""WeCom smart-bot long-connection transport wired to a local Codex app-server.

It speaks the WeCom smart-bot WebSocket protocol (official doc
path/101463): subscribe with BotID/Secret, keep the connection alive with
application-level ping, receive `aibot_msg_callback`, and answer via
`aibot_respond_msg`.

Two loops feed it:

- codex-notify appends one JSON line per completed turn to
  $XDG_STATE_HOME/codex-reply/outbox.jsonl. Each line already carries the
  target chatid resolved by the thread's route; this process only delivers.
  The message is pushed to WeCom as markdown embedding a short `r#xxxxxxxx`
  token, and token -> thread is recorded in tokens.json.
- When the user quotes that message and replies, the callback's quote field
  carries the token; it resolves the token to the thread, starts a turn on
  the local app-server (`turn/start`) and streams the agent text back as a
  WeCom stream message.

The app-server control socket at
$CODEX_HOME/app-server-control/app-server-control.sock speaks websocket over a
Unix socket; a minimal client for it is embedded below so the only external
dependency is the WeCom-facing `websockets` library.

Credentials (bot_id, secret) live in
$XDG_CONFIG_HOME/codex-reply/wechat-work.json, materialized by sops-nix. Logs
go to stderr for journald; credentials, tokens and message content are never
logged.
"""

import argparse
import asyncio
import base64
import json
import logging
import os
import queue
import re
import secrets
import socket
import struct
import sys
import threading
import time
from collections import deque

try:
    from websockets.asyncio.client import connect
except ImportError:  # websockets < 14
    from websockets import connect

WSS_URL = "wss://openws.work.weixin.qq.com"
PING_INTERVAL = 30
TOKEN_RE = re.compile(r"r#([0-9a-f]{8})")
STREAM_FLUSH_INTERVAL = 0.8
MAX_STREAM_CHARS = 20000


class AppServerError(Exception):
    pass


class AppServer:
    """Minimal JSON-RPC client for `codex app-server` over its Unix socket."""

    def __init__(self, path=None):
        self.path = path or os.path.join(
            os.environ.get("CODEX_HOME", os.path.expanduser("~/.codex")),
            "app-server-control",
            "app-server-control.sock",
        )
        self._sock = None
        self._buffer = b""
        self._next_id = 0

    def connect(self):
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(30)
        sock.connect(self.path)
        key = base64.b64encode(os.urandom(16)).decode()
        request = (
            "GET / HTTP/1.1\r\n"
            "Host: localhost\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n"
        )
        sock.sendall(request.encode())
        response = b""
        while b"\r\n\r\n" not in response:
            chunk = sock.recv(4096)
            if not chunk:
                raise AppServerError("app-server closed during handshake")
            response += chunk
        if b"101" not in response.split(b"\r\n", 1)[0]:
            raise AppServerError(f"handshake rejected: {response.splitlines()[0]!r}")
        self._sock = sock
        self._buffer = b""

    def close(self):
        if self._sock is not None:
            try:
                self._sock.close()
            finally:
                self._sock = None

    def _send_text(self, payload):
        data = payload.encode("utf-8")
        mask = os.urandom(4)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
        length = len(data)
        if length < 126:
            header = bytes([0x81, 0x80 | length])
        elif length < 65536:
            header = bytes([0x81, 0x80 | 126]) + struct.pack(">H", length)
        else:
            header = bytes([0x81, 0x80 | 127]) + struct.pack(">Q", length)
        self._sock.sendall(header + mask + masked)

    def _recv_exact(self, size):
        while len(self._buffer) < size:
            chunk = self._sock.recv(65536)
            if not chunk:
                raise ConnectionError("app-server closed the connection")
            self._buffer += chunk
        data, self._buffer = self._buffer[:size], self._buffer[size:]
        return data

    def _recv_text(self):
        parts = []
        while True:
            header = self._recv_exact(2)
            opcode = header[0] & 0x0F
            length = header[1] & 0x7F
            if length == 126:
                length = struct.unpack(">H", self._recv_exact(2))[0]
            elif length == 127:
                length = struct.unpack(">Q", self._recv_exact(8))[0]
            payload = self._recv_exact(length)
            if opcode == 0x9:  # ping -> pong
                mask = os.urandom(4)
                masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
                self._sock.sendall(bytes([0x8A, 0x80 | len(payload)]) + mask + masked)
                continue
            if opcode == 0x8:  # close
                raise ConnectionError("app-server closed the websocket")
            if opcode in (0x1, 0x0):  # text or continuation
                parts.append(payload)
                if header[0] & 0x80:
                    break
        return b"".join(parts).decode("utf-8")

    def _send_json(self, message):
        self._send_text(json.dumps(message))

    def _next_request_id(self):
        self._next_id += 1
        return self._next_id

    def request(self, method, params=None):
        request_id = self._next_request_id()
        self._send_json({"method": method, "id": request_id, "params": params or {}})
        while True:
            message = json.loads(self._recv_text())
            if message.get("id") != request_id:
                continue
            if "error" in message:
                raise AppServerError(f"{method} failed: {message['error']}")
            return message.get("result")

    def notifications(self):
        while True:
            message = json.loads(self._recv_text())
            if "method" in message:
                yield message

    def initialize(self, client_name="codex-reply"):
        self.request(
            "initialize",
            {
                "clientInfo": {"name": client_name, "title": "codex-reply", "version": "0.1"},
                "capabilities": {"experimentalApi": True},
            },
        )
        self._send_json({"method": "initialized", "params": {}})

    def resume_thread(self, thread_id):
        return self.request("thread/resume", {"threadId": thread_id})

    def start_turn(self, thread_id, text):
        return self.request(
            "turn/start",
            {
                "threadId": thread_id,
                "input": [{"type": "text", "text": text}],
            },
        )

    def run_turn(self, thread_id, text):
        """Start a turn and yield ("delta", text) until ("done", status)."""
        self.initialize()
        try:
            self.start_turn(thread_id, text)
        except AppServerError:
            # The thread may not be loaded in this app-server process yet.
            self.resume_thread(thread_id)
            self.start_turn(thread_id, text)
        for notification in self.notifications():
            method = notification.get("method")
            params = notification.get("params", {})
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
    bot_id = config.get("bot_id") or config.get("botid")
    secret = config.get("secret")
    if not bot_id or not secret:
        raise ValueError("config must define bot_id and secret")
    return {
        "bot_id": bot_id,
        "secret": secret,
    }


class Relay:
    def __init__(self, config, ws_url, state_dir, log):
        self.bot_id = config["bot_id"]
        self.secret = config["secret"]
        self.ws_url = ws_url
        self.state_dir = state_dir
        self.outbox = os.path.join(state_dir, "outbox.jsonl")
        self.tokens_path = os.path.join(state_dir, "tokens.json")
        self.last_push_path = os.path.join(state_dir, "last-push.json")
        self.log = log
        self._seq = 0
        self._seen = deque(maxlen=1000)
        self._tokens = {}
        self._last_push = {}
        self._turns = asyncio.Semaphore(4)
        self._load_tokens()
        self._load_last_push()

    def _load_tokens(self):
        try:
            with open(self.tokens_path, encoding="utf-8") as handle:
                data = json.load(handle)
        except (OSError, json.JSONDecodeError):
            return
        cutoff = time.time() - 7 * 86400
        self._tokens = {
            token: entry for token, entry in data.items() if entry.get("created", 0) > cutoff
        }

    def _save_tokens(self):
        os.makedirs(self.state_dir, exist_ok=True)
        with open(self.tokens_path, "w", encoding="utf-8") as handle:
            json.dump(self._tokens, handle)

    def _load_last_push(self):
        try:
            with open(self.last_push_path, encoding="utf-8") as handle:
                data = json.load(handle)
        except (OSError, json.JSONDecodeError):
            return
        self._last_push = {
            chatid: entry
            for chatid, entry in data.items()
            if entry.get("token") in self._tokens
        }

    def _save_last_push(self):
        os.makedirs(self.state_dir, exist_ok=True)
        with open(self.last_push_path, "w", encoding="utf-8") as handle:
            json.dump(self._last_push, handle)

    def _req_id(self):
        self._seq += 1
        return f"codex-reply-{os.getpid()}-{time.time_ns()}-{self._seq}"

    async def _send(self, ws, cmd, body=None, req_id=None):
        payload = {
            "cmd": cmd,
            "headers": {"req_id": req_id or self._req_id()},
            "body": body or {},
        }
        await ws.send(json.dumps(payload))
        return payload["headers"]["req_id"]

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
        if not os.path.exists(self.outbox):
            return
        tmp = self.outbox + ".processing"
        try:
            os.replace(self.outbox, tmp)
        except FileNotFoundError:
            return
        try:
            with open(tmp, encoding="utf-8") as handle:
                lines = handle.readlines()
        finally:
            try:
                os.unlink(tmp)
            except FileNotFoundError:
                pass
        for raw in lines:
            try:
                entry = json.loads(raw)
            except json.JSONDecodeError:
                continue
            thread_id = entry.get("thread") or ""
            target = entry.get("chatid") or ""
            preview = " ".join((entry.get("preview") or "").split())[:120]
            if not thread_id or not target:
                self.log.warning("outbox entry skipped: missing thread or chatid")
                continue
            token = self._new_token(thread_id)
            content = f"**Codex 完成**\n\n{preview}\n\n回复本条消息继续：`r#{token}`"
            await self._send(
                ws,
                "aibot_send_msg",
                {
                    "chatid": target,
                    "chat_type": 1,
                    "msgtype": "markdown",
                    "markdown": {"content": content},
                },
            )
            self.log.info("pushed thread=%s token=r#%s", thread_id, token)
            self._last_push[target] = {
                "token": token,
                "thread": thread_id,
                "at": int(time.time()),
            }
            self._save_last_push()

    async def _outbox_loop(self, ws):
        while True:
            await asyncio.sleep(1)
            try:
                await self._process_outbox(ws)
            except Exception:
                self.log.exception("outbox processing failed")

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
        return f"s{abs(hash(req_id)) % 10**12:012d}"

    async def _run_turn(self, ws, callback, thread_id, text):
        stream_id = self._stream_id(callback)
        app = AppServer()
        parts = []
        last_flush = 0.0
        status = None
        result_queue = queue.Queue()
        try:
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
            async with self._turns:
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

            async def receive():
                nonlocal subscribed
                async for raw in ws:
                    last_activity[0] = time.monotonic()
                    message = json.loads(raw)
                    cmd = message.get("cmd")
                    if cmd == "aibot_msg_callback":
                        await self._handle_callback(ws, message)
                    elif cmd == "aibot_event_callback":
                        event = message.get("body", {}).get("event", {}).get("eventtype")
                        self.log.info("event=%s", event)
                        if event == "disconnected_event":
                            raise ConnectionError("connection superseded by another client")
                    else:
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

            async def heartbeat():
                while True:
                    await asyncio.sleep(PING_INTERVAL)
                    await self._send(ws, "ping")

            async def watchdog():
                while True:
                    await asyncio.sleep(30)
                    if time.monotonic() - last_activity[0] > 90:
                        raise ConnectionError("no server activity for 90s")

            await asyncio.gather(receive(), heartbeat(), self._outbox_loop(ws), watchdog())

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
        "codex-reply",
        "wechat-work.json",
    )
    parser.add_argument(
        "--config",
        default=os.environ.get("WECHAT_WORK_CONFIG") or default_config,
        help="JSON file with bot_id and secret",
    )
    parser.add_argument("--ws-url", default=WSS_URL)
    parser.add_argument(
        "--state-dir",
        default=os.path.join(
            os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
            "codex-reply",
        ),
    )
    parser.add_argument("--log-level", default="INFO")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=args.log_level,
        format="[%(asctime)s] %(levelname)s %(name)s %(message)s",
        stream=sys.stderr,
    )
    log = logging.getLogger("codex-reply")

    if not os.path.exists(args.config):
        log.error("config %s not found; create it with bot_id and secret", args.config)
        return 0
    try:
        config = load_config(args.config)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        log.error("cannot load config: %s", exc)
        return 1

    relay = Relay(config, args.ws_url, args.state_dir, log)
    try:
        return asyncio.run(relay.run())
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    sys.exit(main())
