#!/usr/bin/env python3
"""Local TOTP helper; HOTP adapted from https://github.com/susam/mintotp."""

import argparse
import base64
import binascii
import hmac
import os
import shutil
import struct
import subprocess
import sys
import time
from pathlib import Path


def hotp(key, counter, digits=6, digest="sha1"):
    key = base64.b32decode(key.upper() + "=" * ((8 - len(key)) % 8))
    mac = hmac.new(key, struct.pack(">Q", counter), digest).digest()
    offset = mac[-1] & 0x0F
    value = struct.unpack(">L", mac[offset : offset + 4])[0] & 0x7FFFFFFF
    return str(value % (10**digits)).zfill(digits)


def copy_code(code):
    commands = []
    if sys.platform == "darwin":
        commands.append(["/usr/bin/pbcopy"])
    commands.append(["clip.exe"])
    if os.environ.get("WAYLAND_DISPLAY"):
        commands.append(["wl-copy"])
    if os.environ.get("DISPLAY"):
        commands.extend([["xclip", "-selection", "clipboard"], ["xsel", "--clipboard", "--input"]])
    if os.environ.get("TMUX"):
        commands.append(["tmux", "load-buffer", "-w", "-"])
    for command in commands:
        if shutil.which(command[0]):
            try:
                subprocess.run(
                    command, input=code.encode(), check=True, stderr=subprocess.DEVNULL, timeout=5
                )
                return True
            except (OSError, subprocess.SubprocessError):
                continue
    return False


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Generate a six-digit TOTP code and copy it to the clipboard."
    )
    parser.add_argument("site", nargs="?")
    parser.add_argument("--list", action="store_true", help="list configured sites")
    parser.add_argument("--no-copy", action="store_true", help="only print the code")
    args = parser.parse_args(argv)
    keys = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "2fa" / "keys"
    if args.list:
        if keys.is_dir():
            for path in sorted(keys.iterdir()):
                if path.is_file():
                    print(path.name)
        return 0
    if not args.site or args.site in {".", ".."} or "/" in args.site:
        parser.error("a site name is required (use --list to see available sites)")
    try:
        key = (keys / args.site).read_text().strip()
        if not key:
            raise ValueError("empty key")
        code = hotp(key, int(time.time() // 30))
    except (OSError, UnicodeError, ValueError, binascii.Error):
        print(f"2fa: cannot read a valid key for {args.site!r}", file=sys.stderr)
        return 1
    print(code, flush=True)
    if not args.no_copy and not copy_code(code):
        print("2fa: clipboard unavailable; use the printed code", file=sys.stderr)
    return 0
