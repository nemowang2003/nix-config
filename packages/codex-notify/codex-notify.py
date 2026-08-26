"""Codex notification glue, driven entirely by lifecycle hooks.

Hook wiring lives in home-manager/profiles/agents/codex/default.nix:

- UserPromptSubmit -> `codex-notify prompt`
    Stamps the per-thread turn start. /goal continuation turns bypass this
    hook (they are submitted as internal response items), which is exactly
    what lets us tell user turns from autonomous goal checkpoints.
- Stop -> `codex-notify notify Codex 300`
    Runs at the end of every turn and performs the actual notification. It
    always exits 0: a non-zero Stop hook exit would block or continue the
    turn.

State is one JSON file per thread at
$XDG_STATE_HOME/codex-notify/<sha256(thread)>.json with the fields `prompt`
(epoch of the last UserPromptSubmit), `notify` (epoch of the last turn end)
and `profile` (route name).

Codex has no thread-deletion hook (SessionEnd fires on every teardown with a
constant reason), so the sqlite `threads` table is the source of truth: on
each hook invocation any state file whose thread no longer exists is pruned.
No time-based expiry is used - a route for a dormant thread must survive as
long as the conversation does.

The route map lives in $XDG_CONFIG_HOME/codex-notify/routes.json,
materialized by sops-nix from secrets/common/routes.json. Each entry carries
both the ServerChan push URL and the WeCom single-chat userid for one person;
the WeCom half is handed to the codex-reply long-connection on dt-w01 through
the outbox, which decides nothing on its own. Only profile names are ever
logged; URLs and userids appear solely in short-lived argv or outbox lines.
"""

import base64
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
import time

CURL = "@curl@"
FZF = "@fzf@"

DEFAULT_PROFILE = "me"
DEFAULT_THRESHOLD = 300

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
    "codex-reply",
    "outbox.jsonl",
)

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
        pass


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
        with open(tmp, "w") as handle:
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


def notify_local(title, content):
    release = platform.uname().release.lower()
    if "microsoft" not in release and "wsl" not in release:
        return
    powershell = shutil.which("powershell.exe")
    if not powershell:
        return
    b64_title = base64.b64encode(clean_control_chars(title).encode()).decode()
    b64_body = base64.b64encode(clean_control_chars(content).encode()).decode()
    script = PS_TOAST_SCRIPT % (b64_title, b64_body)
    try:
        subprocess.run(
            [powershell, "-NonInteractive", "-WindowStyle", "Hidden", "-Command", script],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired):
        pass


def queue_wecom_push(thread_id, content, chatid):
    """Ask the dt-w01 WeCom long-connection to push a replyable notification.

    The chatid is resolved here from the thread's route; the transport on the
    other end of the outbox only delivers, it never picks a target.
    """
    try:
        os.makedirs(os.path.dirname(reply_outbox), exist_ok=True)
        preview = " ".join(content.split())
        entry = json.dumps(
            {
                "thread": thread_id,
                "preview": preview,
                "chatid": chatid,
                "at": int(time.time()),
            }
        )
        with open(reply_outbox, "a", encoding="utf-8") as handle:
            handle.write(entry + "\n")
    except OSError:
        log("notify wecom outbox write failed")


def send_serverchan(title, content, url):
    log(f"serverchan title={title} content_bytes={len(content.encode())}")
    try:
        result = subprocess.run(
            [
                CURL,
                "--fail",
                "--silent",
                "--show-error",
                "--max-time",
                "10",
                "--request",
                "POST",
                "--data-urlencode",
                f"title={title}",
                "--data-urlencode",
                f"desp={content}",
                "--output",
                os.devnull,
                "--write-out",
                "%{http_code}",
                url,
            ],
            capture_output=True,
            text=True,
            timeout=15,
        )
        http_code = result.stdout.strip()
        log(f"serverchan done http_code={http_code} rc={result.returncode}")
        return result.returncode
    except (OSError, subprocess.TimeoutExpired) as error:
        log(f"serverchan error: {type(error).__name__}")
        return 1


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


def cmd_prompt():
    payload = stdin_json()
    thread_id = payload.get("session_id") or ""
    if not thread_id:
        log("prompt: no session_id in hook payload")
        return 0
    state = load_state(thread_id)
    state["prompt"] = int(time.time())
    save_state(thread_id, state)
    cleanup_orphaned_state()
    log(f"prompt session={thread_id} marker={key_for(thread_id)}")
    return 0


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
    cleanup_orphaned_state()
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
    selection = fzf_select("session> ", "\n".join(f"{tid}  {title}" for tid, title in rows))
    if not selection:
        return 0
    thread_id = selection.split(" ", 1)[0]
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
    try:
        threshold = int(args[2]) if len(args) > 2 else DEFAULT_THRESHOLD
    except ValueError:
        threshold = DEFAULT_THRESHOLD
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

    notify_local(full_title, content)
    log("notify local done")

    state = load_state(thread_id)
    now = time.time()
    prompt = state.get("prompt")
    last_notify = state.get("notify")
    duration = -1
    is_goal = False
    if prompt is not None and last_notify is not None and prompt < last_notify:
        # No user prompt since the previous turn end: autonomous goal
        # checkpoint.
        is_goal = True
        log(f"notify turn=goal thread={thread_id}")
    elif prompt is not None:
        # User-driven turn: ping only when this turn itself ran long enough.
        if now >= prompt:
            duration = int(now - prompt)
        log(f"notify turn=user thread={thread_id} duration={duration}")
    else:
        # No prompt marker: a resumed paused goal can start running with no
        # UserPromptSubmit at all, so treat it as autonomous too.
        is_goal = True
        log(f"notify turn=goal thread={thread_id} no-prompt")

    profile = state.get("profile") or DEFAULT_PROFILE
    route = load_routes().get(profile) or {}
    url = route.get("serverchan") or ""
    chatid = route.get("wecom") or ""
    if is_goal:
        log(f"notify serverchan mode=goal unconditional=yes route={profile}")
        if not url:
            log("notify serverchan skip: url profile missing")
        else:
            rc = send_serverchan(full_title, content, url)
            log(f"notify serverchan done rc={rc}")
    elif duration >= threshold:
        log(
            f"notify serverchan mode=user duration={duration} threshold={threshold} route={profile}"
        )
        if not url:
            log("notify serverchan skip: url profile missing")
        else:
            rc = send_serverchan(full_title, content, url)
            log(f"notify serverchan done rc={rc}")
    else:
        log(f"notify serverchan skip duration={duration} threshold={threshold}")

    if is_goal or duration >= threshold:
        if chatid:
            queue_wecom_push(thread_id, content, chatid)
        else:
            log(f"notify wecom skip: route {profile} has no wecom userid")

    state["notify"] = int(now)
    save_state(thread_id, state)
    cleanup_orphaned_state()
    return 0


def main(argv):
    command = argv[1] if len(argv) > 1 else ""
    try:
        if command == "prompt":
            return cmd_prompt()
        if command == "route":
            return cmd_route(argv[1:])
        if command == "pick":
            return cmd_pick()
        if command == "notify":
            return cmd_notify(argv[1:])
        log(f"unknown subcommand: {command}")
        return 0
    except Exception:
        # A Stop hook must never block the turn: exit 0 on unexpected errors.
        log("notify exception: unexpected error")
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
