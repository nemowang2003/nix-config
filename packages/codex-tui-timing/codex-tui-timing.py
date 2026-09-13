"""Measure Codex TUI startup and EOF-exit latency for one codex binary.

The TUI only renders against a real terminal, so each run happens inside a
detached tmux session. "Ready" means the pane shows the chat composer or its
status line instead of a startup draft, an onboarding animation or a trust
dialog; the marker is configurable for other versions.

Usage:
  codex-tui-timing <codex-binary> [--home DIR] [--cwd DIR] [--runs N]
"""

import argparse
import os
import re
import statistics
import subprocess
import sys
import time

TMUX = "@tmux@"
DEFAULT_READY_PATTERN = r"Ask Codex to do anything|Context \d+% left|· Ready ·"
BLOCKING_PATTERNS = ("welcome to codex", "hooks need review", "do you trust")


def tmux(sock, *args, check=False):
    return subprocess.run(
        [TMUX, "-L", sock, *args], capture_output=True, text=True, check=check
    )


def capture(sock, session):
    return tmux(sock, "capture-pane", "-pt", session).stdout


def session_alive(sock, session):
    result = tmux(sock, "list-panes", "-t", session, "-F", "#{pane_dead}")
    return result.returncode == 0 and result.stdout.strip() == "0"


def wait_until_ready(sock, session, timeout, pattern):
    """Return seconds until the composer/status line appears, else None."""
    ready = re.compile(pattern, re.IGNORECASE)
    start = time.monotonic()
    while time.monotonic() - start < timeout:
        pane = capture(sock, session)
        lowered = pane.lower()
        blocked = any(text in lowered for text in BLOCKING_PATTERNS)
        if ready.search(pane) and not blocked:
            return time.monotonic() - start
        time.sleep(0.2)
    return None


def wait_for_exit(sock, session, timeout):
    start = time.monotonic()
    while time.monotonic() - start < timeout:
        if not session_alive(sock, session):
            return time.monotonic() - start
        time.sleep(0.05)
    return None


def one_run(sock, session, binary, home, cwd, ready_timeout, exit_timeout, pattern):
    tmux(sock, "new-session", "-d", "-s", session, "-x", "160", "-y", "45",
         "-c", cwd, f"env CODEX_HOME={home} {binary}", check=True)
    startup = wait_until_ready(sock, session, ready_timeout, pattern)
    pane = capture(sock, session)
    tmux(sock, "send-keys", "-t", session, "C-d")
    exit_time = wait_for_exit(sock, session, exit_timeout)
    tmux(sock, "kill-server")
    return startup, exit_time, pane


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("binary", help="path to the codex binary to measure")
    parser.add_argument("--home", default=os.path.expanduser("~/.codex"),
                        help="CODEX_HOME to use (default: ~/.codex)")
    parser.add_argument("--cwd", default=os.getcwd(),
                        help="working directory for the TUI (default: cwd)")
    parser.add_argument("--runs", type=int, default=2)
    parser.add_argument("--ready-timeout", type=float, default=120.0)
    parser.add_argument("--exit-timeout", type=float, default=60.0)
    parser.add_argument("--ready-pattern", default=DEFAULT_READY_PATTERN,
                        help="regex that marks the chat composer as ready")
    args = parser.parse_args(argv)

    if not os.path.exists(args.binary):
        parser.error(f"binary not found: {args.binary}")

    sock = f"codex-tui-timing-{os.getpid()}"
    tmux(sock, "kill-server")
    version = subprocess.run([args.binary, "--version"], capture_output=True,
                             text=True).stdout.strip()
    print(f"binary : {args.binary}")
    print(f"version: {version or '(unknown)'}")
    print(f"home   : {args.home}\ncwd    : {args.cwd}")
    starts, exits = [], []
    for index in range(1, args.runs + 1):
        startup, exit_time, pane = one_run(
            sock, f"run{index}", args.binary, args.home, args.cwd,
            args.ready_timeout, args.exit_timeout, args.ready_pattern,
        )
        starts.append(startup)
        exits.append(exit_time)
        startup_text = f"{startup:.2f}s" if startup is not None else "timeout"
        exit_text = f"{exit_time:.2f}s" if exit_time is not None else "timeout"
        print(f"  run {index}: startup {startup_text} | EOF->exit {exit_text}")
        first_lines = [line.strip() for line in pane.splitlines() if line.strip()][:3]
        print(f"           pane: {first_lines}")

    def summary(name, values):
        done = [value for value in values if value is not None]
        if done:
            print(f"{name}: median {statistics.median(done):.2f}s over {len(done)}/{len(values)} runs")
        else:
            print(f"{name}: no successful run")
    summary("startup  ", starts)
    summary("EOF->exit", exits)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
