"""Codex notification glue, driven entirely by lifecycle hooks.

Hook wiring lives in home-manager/profiles/agents/codex/default.nix:

- Stop -> `codex-notify notify Codex`
    Runs at the end of every turn and performs the actual notification. It
    always exits 0: a non-zero Stop hook exit would block or continue the
    turn.

State is one JSON file per thread at
$XDG_STATE_HOME/codex-notify/<sha256(thread)>.json with the `profile` (route
name).

Codex has no thread-deletion hook (SessionEnd fires on every teardown with a
constant reason), so the sqlite `threads` table is the source of truth.
Pruning is deliberately NOT on the hot hook path; run `codex-notify cleanup`
manually to remove state files whose thread no longer exists. No time-based
expiry is used - a route for a dormant thread must survive as long as the
conversation does.

The route map lives in $XDG_CONFIG_HOME/codex-notify/routes.json,
materialized by sops-nix from secrets/common/routes.json. Each entry carries
both the ServerChan push URL and the WeCom single-chat userid for one person;
the WeCom half is handed to the codex-wecom-relay on dt-w01 through
the outbox, which decides nothing on its own. Only profile names are ever
logged; URLs and userids appear solely in short-lived argv or outbox lines.
"""

import base64
import fcntl
import hashlib
import json
import os
import platform
import re
import shutil
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time
import uuid

import httpx

FZF = os.environ.get("CODEX_NOTIFY_FZF") or shutil.which("fzf") or "fzf"

DEFAULT_PROFILE = "me"

state_dir = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
    "codex-notify",
)
log_dir = os.path.join(
    os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
    "codex-notify",
)
config_dir = os.path.join(
    os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")),
    "codex-notify",
)
routes_file = os.path.join(config_dir, "routes.json")
reply_outbox = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
    "codex-wecom-relay",
    "outbox.jsonl",
)
serverchan_outbox = os.path.join(state_dir, "serverchan-outbox")
SERVERCHAN_RETRY_DELAYS = (2, 5)

PS_TOAST_SCRIPT = """
$t = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("%s"));
$b = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("%s"));
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null;
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null;
$xmlText = "<toast><visual><binding template=""ToastGeneric""><text>{0}</text><text>{1}</text></binding></visual></toast>" -f [System.Security.SecurityElement]::Escape($t), [System.Security.SecurityElement]::Escape($b);
$doc = New-Object Windows.Data.Xml.Dom.XmlDocument;
$doc.LoadXml($xmlText);
$toast = New-Object Windows.UI.Notifications.ToastNotification($doc);
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Microsoft.WindowsTerminal_8wekyb3d8bbwe!App").Show($toast);
"""


def log(msg):
    try:
        os.makedirs(log_dir, exist_ok=True)
        with open(os.path.join(log_dir, "notify.log"), "a") as handle:
            handle.write(f"[{time.strftime('%F %T %z')}] {msg}\n")
    except OSError:
        print(f"codex-notify: {msg}", file=sys.stderr)


def key_for(thread_id):
    return hashlib.sha256(thread_id.encode()).hexdigest()


def state_path(thread_id):
    return os.path.join(state_dir, f"{key_for(thread_id)}.json")


def load_state(thread_id):
    try:
        with open(state_path(thread_id)) as handle:
            data = json.load(handle)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_state(thread_id, state):
    try:
        os.makedirs(state_dir, exist_ok=True)
        path = state_path(thread_id)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as handle:
            json.dump(state, handle)
        os.replace(tmp, path)
    except OSError:
        log(f"state write failed thread={thread_id}")


def codex_db_path():
    return os.path.join(
        os.environ.get("CODEX_HOME", os.path.expanduser("~/.codex")),
        "state_5.sqlite",
    )


def known_thread_hashes():
    """Hash set of every thread id in the sqlite thread store.

    Returns None when the store cannot be read so callers can refuse to prune
    rather than risk deleting state on a transient failure.
    """
    try:
        connection = sqlite3.connect(f"file:{codex_db_path()}?mode=ro", uri=True)
        rows = connection.execute("SELECT id FROM threads").fetchall()
        connection.close()
        return {hashlib.sha256(thread_id.encode()).hexdigest() for (thread_id,) in rows}
    except sqlite3.Error:
        return None


def cleanup_orphaned_state():
    known = known_thread_hashes()
    if known is None:
        return
    try:
        for name in os.listdir(state_dir):
            path = os.path.join(state_dir, name)
            try:
                if name.endswith(".json") and name[: -len(".json")] not in known:
                    os.unlink(path)
                    log(f"state cleanup removed orphaned {name}")
            except OSError:
                pass
    except OSError:
        pass


def cmd_cleanup():
    cleanup_orphaned_state()
    log("cleanup done")
    return 0


def load_routes():
    try:
        with open(routes_file) as handle:
            data = json.load(handle)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def stdin_json():
    try:
        data = json.load(sys.stdin)
        return data if isinstance(data, dict) else {}
    except (ValueError, TypeError):
        return {}


def clean_control_chars(text):
    return "".join(ch for ch in text if not (ord(ch) < 32 or ord(ch) == 127))


def wecom_markdown(content):
    """Normalize the assistant text for the WeCom push, keeping its structure.

    WeCom renders markdown, where a single newline already breaks the line and
    a blank line separates paragraphs (both appear in the official sample), so
    the answer must not be flattened into one run-on line. Only trailing
    whitespace and runs of blank lines are dropped, which keeps a wall of empty
    lines from pushing the reply hint out of the message.
    """
    normalized = []
    previous_blank = False
    for line in content.strip().splitlines():
        line = line.rstrip()
        if line:
            previous_blank = False
        elif previous_blank:
            continue
        else:
            previous_blank = True
        normalized.append(line)
    return "\n".join(normalized)


def notify_local(title, content):
    release = platform.uname().release.lower()
    if "microsoft" not in release and "wsl" not in release:
        return
    powershell = shutil.which("powershell.exe")
    if not powershell:
        log("notify local failed: powershell.exe unavailable")
        return
    b64_title = base64.b64encode(clean_control_chars(title).encode()).decode()
    b64_body = base64.b64encode(clean_control_chars(content).encode()).decode()
    script = PS_TOAST_SCRIPT % (b64_title, b64_body)
    try:
        result = subprocess.run(
            [powershell, "-NonInteractive", "-WindowStyle", "Hidden", "-Command", script],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=30,
        )
        if result.returncode:
            log(f"notify local failed: exit_code={result.returncode}")
    except (OSError, subprocess.TimeoutExpired) as error:
        log(f"notify local failed: {type(error).__name__}")


def queue_wecom_push(thread_id, content, chatid):
    """Ask the dt-w01 WeCom long-connection to push a replyable notification.

    The chatid is resolved here from the thread's route; the transport on the
    other end of the outbox only delivers, it never picks a target.
    """
    try:
        os.makedirs(os.path.dirname(reply_outbox), exist_ok=True)
        entry = json.dumps(
            {
                "thread": thread_id,
                "content": wecom_markdown(content),
                "chatid": chatid,
                "at": int(time.time()),
            }
        )
        line = (entry + "\n").encode()
        fd = os.open(reply_outbox, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        try:
            if os.write(fd, line) != len(line):
                raise OSError("short outbox write")
            os.fsync(fd)
        finally:
            os.close(fd)
        log(f"notify wecom queued thread={thread_id}")
    except OSError as error:
        log(f"notify wecom outbox write failed: {type(error).__name__}")


def save_serverchan_item(path, item):
    os.makedirs(serverchan_outbox, mode=0o700, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=serverchan_outbox, prefix=".pending-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(item, handle)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def queue_serverchan(thread_id, turn_id, title, content, profile):
    item_id = key_for(f"{thread_id}:{turn_id}") if turn_id else uuid.uuid4().hex
    path = os.path.join(serverchan_outbox, f"{item_id}.json")
    try:
        save_serverchan_item(
            path,
            {
                "thread": thread_id,
                "turn": turn_id,
                "title": title,
                "content": content,
                "profile": profile,
                "attempts": 0,
            },
        )
        log(f"serverchan queued thread={thread_id} turn={turn_id}")
    except OSError as error:
        log(f"serverchan queue failed: {type(error).__name__} thread={thread_id}")


def send_serverchan(title, content, url):
    log(f"serverchan title={title} content_bytes={len(content.encode())}")
    try:
        response = httpx.post(
            url,
            data={"title": title, "desp": content},
            timeout=httpx.Timeout(15, connect=10),
            trust_env=False,
        )
        response.raise_for_status()
        try:
            body = response.json()
        except ValueError:
            log("serverchan error: invalid JSON response")
            return 1
        if not isinstance(body, dict) or body.get("code") != 0:
            code = body.get("code") if isinstance(body, dict) else None
            safe_code = code if isinstance(code, int) and not isinstance(code, bool) else "invalid"
            log(f"serverchan error: api_code={safe_code}")
            return 1
        log(f"serverchan done http_code={response.status_code}")
        return 0
    except httpx.HTTPStatusError as error:
        log(f"serverchan error: http_code={error.response.status_code}")
        return 1
    except httpx.HTTPError as error:
        log(f"serverchan error: {type(error).__name__}")
        return 1


def drain_serverchan():
    if not os.path.isdir(serverchan_outbox):
        return
    lock_path = os.path.join(state_dir, "serverchan-drain.lock")
    fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        # Only the detached worker waits for this lock. A concurrent hook may
        # enqueue after the first worker lists the directory, so its own worker
        # must wait and drain rather than silently leave that message behind.
        fcntl.flock(fd, fcntl.LOCK_EX)
        for name in sorted(os.listdir(serverchan_outbox)):
            if not name.endswith(".json"):
                continue
            path = os.path.join(serverchan_outbox, name)
            try:
                with open(path, encoding="utf-8") as handle:
                    item = json.load(handle)
            except (OSError, ValueError) as error:
                log(f"serverchan queue read failed: {name} {type(error).__name__}")
                continue
            if not isinstance(item, dict) or not all(
                isinstance(item.get(field), str) for field in ("title", "content", "profile")
            ):
                log(f"serverchan queue invalid: {name}")
                continue
            profile = item.get("profile") or DEFAULT_PROFILE
            url = (load_routes().get(profile) or {}).get("serverchan") or ""
            if not url:
                log(f"serverchan route missing: profile={profile}")
                continue
            for delay in (0, *SERVERCHAN_RETRY_DELAYS):
                if delay:
                    time.sleep(delay)
                if send_serverchan(item["title"], item["content"], url) == 0:
                    os.unlink(path)
                    log(f"serverchan delivered thread={item.get('thread')} turn={item.get('turn')}")
                    break
                item["attempts"] = item.get("attempts", 0) + 1
                save_serverchan_item(path, item)
                if delay != SERVERCHAN_RETRY_DELAYS[-1]:
                    log(f"serverchan delivery failed thread={item.get('thread')} retrying")
            else:
                log(f"serverchan delivery failed thread={item.get('thread')} retained for next hook")
    finally:
        os.close(fd)


def dispatch_notifications(title, content):
    """Deliver slow notifications outside the hook's timeout budget."""
    try:
        pid = os.fork()
    except OSError as error:
        log(f"notification dispatch failed: {type(error).__name__}")
        return
    if pid:
        log(f"notification dispatch pid={pid}")
        return

    try:
        os.setsid()
        with open(os.devnull, "rb") as stdin, open(os.devnull, "ab") as output:
            os.dup2(stdin.fileno(), sys.stdin.fileno())
            os.dup2(output.fileno(), sys.stdout.fileno())
            os.dup2(output.fileno(), sys.stderr.fileno())

        notify_local(title, content)
        drain_serverchan()
    except Exception as error:
        log(f"notification delivery exception: {type(error).__name__}")
    finally:
        os._exit(0)


def fzf_select(prompt, feed):
    try:
        result = subprocess.run(
            [FZF, f"--prompt={prompt}"],
            input=feed,
            text=True,
            stdout=subprocess.PIPE,
        )
        if result.returncode != 0:
            return ""
        return result.stdout.rstrip("\n")
    except OSError:
        return ""


def cmd_route(args):
    thread_id = args[1] if len(args) > 1 else ""
    name = args[2] if len(args) > 2 else ""
    if not thread_id:
        print("usage: codex-notify route <thread-id> [name]", file=sys.stderr)
        return 1
    if name and not re.fullmatch(r"[A-Za-z0-9_]+", name):
        print("route name must match [A-Za-z0-9_]+", file=sys.stderr)
        return 1
    if name and name not in load_routes():
        print(f"unknown route profile: {name}", file=sys.stderr)
        return 1
    state = load_state(thread_id)
    if name:
        state["profile"] = name
    else:
        state.pop("profile", None)
    save_state(thread_id, state)
    log(f"route thread={thread_id} suffix={name}" if name else f"route thread={thread_id} cleared")
    return 0


def cmd_pick():
    db = codex_db_path()
    try:
        connection = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        rows = connection.execute(
            "SELECT id, COALESCE(title, '(untitled)') FROM threads ORDER BY updated_at DESC"
        ).fetchall()
        connection.close()
    except sqlite3.Error as error:
        print(f"cannot read {db}: {error}", file=sys.stderr)
        return 1
    if not rows:
        print("no threads found", file=sys.stderr)
        return 1
    # Thread titles can contain newlines, so never rely on fzf's line layout
    # to carry the id back. Feed one line per thread with a TAB separator and
    # a flattened title; parse the id from the part before the first TAB.
    lines = [f"{tid}\t{re.sub(r'\s+', ' ', title).strip()}" for tid, title in rows]
    selection = fzf_select("session> ", "\n".join(lines))
    if not selection:
        return 0
    thread_id = selection.split("\t", 1)[0]
    names = sorted(load_routes(), key=lambda name: (name != DEFAULT_PROFILE, name))
    if not names:
        print("routes.json has no profiles", file=sys.stderr)
        return 1
    profile = fzf_select("route> ", "\n".join(names))
    if not profile:
        return 0
    return cmd_route(["route", thread_id, profile])


def cmd_notify(args):
    title = args[1] if len(args) > 1 else "Codex"
    wecom_enabled = "--wecom-relay" in args[2:]
    payload = stdin_json()

    # A blocking Stop hook elsewhere re-runs the whole Stop set in the same
    # turn with stop_hook_active=true; skip those repeats so one turn pings
    # exactly once.
    if payload.get("stop_hook_active"):
        log("notify skip: stop_hook_active=true (repeat run)")
        return 0

    thread_id = payload.get("session_id") or ""
    turn_id = payload.get("turn_id") or ""
    content = payload.get("last_assistant_message") or "Task complete"
    host = socket.gethostname().split(".")[0]
    full_title = f"{title}@{host}" if host else title
    log(f"notify stop thread={thread_id} turn={turn_id} content_bytes={len(content.encode())}")

    state = load_state(thread_id)
    profile = state.get("profile") or DEFAULT_PROFILE
    route = load_routes().get(profile) or {}
    url = route.get("serverchan") or ""
    chatid = route.get("wecom") or ""
    if url:
        queue_serverchan(thread_id, turn_id, full_title, content, profile)
    else:
        log("notify serverchan skip: url profile missing")

    if chatid and wecom_enabled:
        queue_wecom_push(thread_id, content, chatid)
    elif chatid:
        log("notify wecom skip: no relay configured on this host")
    else:
        log(f"notify wecom skip: route {profile} has no wecom userid")

    dispatch_notifications(full_title, content)
    return 0


def main(argv):
    command = argv[1] if len(argv) > 1 else ""
    try:
        if command == "cleanup":
            return cmd_cleanup()
        if command == "route":
            return cmd_route(argv[1:])
        if command == "pick":
            return cmd_pick()
        if command == "notify":
            return cmd_notify(argv[1:])
        if command == "drain":
            drain_serverchan()
            return 0
        log(f"unknown subcommand: {command}")
        return 0
    except Exception as error:
        log(f"{command or 'unknown'} exception: {type(error).__name__}")
        # Lifecycle hooks must never block a turn. Interactive maintenance
        # commands, however, should report failures to their caller.
        if command == "notify":
            return 0
        print(f"codex-notify: {error}", file=sys.stderr)
        return 1


def cli():
    return main(sys.argv)


if __name__ == "__main__":
    sys.exit(cli())
