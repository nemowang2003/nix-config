"""Archive the parent thread after Codex edits an earlier prompt.

The SessionStart hook identifies forked sessions. A normal ``codex fork``
copies the complete parent history, while backtracking deliberately omits one
or more user turns. Only the latter is archived here.
"""

from __future__ import annotations

import argparse
from datetime import datetime
import json
import os
import sqlite3
import subprocess
import sys
from pathlib import Path
from typing import Any


def read_json_line(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as stream:
        value = json.loads(stream.readline())
    if not isinstance(value, dict):
        raise ValueError(f"expected a JSON object in {path}")
    return value


def parse_timestamp(value: Any) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def omitted_user_message(
    parent_path: Path, byte_offset: int, forked_at: datetime
) -> bool:
    """Return whether the fork cutoff removed a user message before the fork."""
    if byte_offset < 0 or byte_offset >= parent_path.stat().st_size:
        return False

    with parent_path.open("rb") as stream:
        stream.seek(byte_offset)
        for raw_line in stream:
            try:
                event = json.loads(raw_line)
            except (UnicodeDecodeError, json.JSONDecodeError):
                continue
            payload = event.get("payload", {})
            if (
                event.get("type") == "response_item"
                and payload.get("type") == "message"
                and payload.get("role") == "user"
            ):
                event_time = parse_timestamp(event.get("timestamp"))
                if event_time is not None and event_time <= forked_at:
                    return True
    return False


def parent_for_backtrack(
    hook_input: dict[str, Any], db_path: Path
) -> str | None:
    """Find the parent only when this SessionStart came from backtracking."""
    if hook_input.get("hook_event_name") != "SessionStart":
        return None
    if hook_input.get("source") != "fork":
        return None

    transcript_value = hook_input.get("transcript_path")
    if not isinstance(transcript_value, str) or not transcript_value:
        return None
    transcript_path = Path(transcript_value)
    meta = read_json_line(transcript_path).get("payload", {})
    if meta.get("id") != hook_input.get("session_id"):
        raise ValueError("hook session id does not match rollout metadata")

    parent_id = meta.get("forked_from_id")
    history_base = meta.get("history_base")
    forked_at = parse_timestamp(meta.get("timestamp"))
    if (
        not isinstance(parent_id, str)
        or not isinstance(history_base, dict)
        or forked_at is None
    ):
        return None
    cutoff = history_base.get("end_byte_offset")
    if not isinstance(cutoff, int):
        return None

    with sqlite3.connect(f"file:{db_path}?mode=ro", uri=True) as connection:
        row = connection.execute(
            "SELECT rollout_path, archived FROM threads WHERE id = ?",
            (parent_id,),
        ).fetchone()
    if row is None or row[1]:
        return None

    parent_path = Path(row[0])
    if not parent_path.is_file() or not omitted_user_message(
        parent_path, cutoff, forked_at
    ):
        return None
    return parent_id


def archive_thread(codex: str, thread_id: str) -> None:
    result = subprocess.run(
        [codex, "archive", thread_id],
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        fallback = f"codex archive exited with {result.returncode}"
        raise RuntimeError(detail or fallback)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--codex", default="codex", help="Codex executable")
    parser.add_argument(
        "--codex-home",
        type=Path,
        default=Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        hook_input = json.load(sys.stdin)
        if not isinstance(hook_input, dict):
            raise ValueError("hook input must be a JSON object")
        parent_id = parent_for_backtrack(
            hook_input, args.codex_home / "state_5.sqlite"
        )
        if parent_id is not None:
            archive_thread(args.codex, parent_id)
    except Exception as error:
        print(f"codex-archive-backtrack: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
