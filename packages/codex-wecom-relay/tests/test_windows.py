import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import codex_wecom_relay as relay_module


class WindowsAppServerTests(unittest.IsolatedAsyncioTestCase):
    def test_native_paths_require_absolute_drive_paths(self):
        self.assertEqual(
            relay_module.windows_drive_path(r"C:\Users\测试 user\.codex"),
            Path("/mnt/c/Users/测试 user/.codex").resolve(),
        )
        for path in [r"C:relative", r"\\server\share\codex.exe", "/tmp/codex.exe"]:
            with self.subTest(path=path), self.assertRaises(relay_module.AppServerError):
                relay_module.windows_drive_path(path)

    async def test_stdio_queue_preserves_unicode_and_submission_identity_without_resuming(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            native_home = r"C:\Users\test\.codex"
            native_bin = r"C:\Program Files\ChatGPT\codex.exe"
            executable = home / "codex.exe"
            # Run a real stdio peer on every test platform without Windows or a model.
            executable.write_text(
                f"#!{sys.executable}\n"
                "import json, os, pathlib, sys\n"
                "record = pathlib.Path('requests.jsonl')\n"
                "record.write_text(json.dumps({'home': os.environ['CODEX_HOME'], "
                "'wslenv': os.environ['WSLENV']}) + '\\n')\n"
                "for line in sys.stdin:\n"
                "    message = json.loads(line)\n"
                "    with record.open('a') as output:\n"
                "        output.write(json.dumps(message, ensure_ascii=False) + '\\n')\n"
                "    if 'id' not in message: continue\n"
                "    if message['method'] == 'initialize': result = {}\n"
                "    elif message['method'] == 'thread/queue/add':\n"
                "        result = {'queuedSubmission': {'id': 'queued-id'}}\n"
                "    else: raise RuntimeError('Unexpected RPC: ' + message['method'])\n"
                "    print(json.dumps({'id': message['id'], 'result': result}), flush=True)\n"
            )
            executable.chmod(0o755)
            (home / "wsl-bridge.json").write_text(
                json.dumps({"codexHome": native_home, "codexExecutable": native_bin})
            )
            app = relay_module.WindowsAppServer(home)
            states = []
            app.on_submission = lambda state, submission_id=None: states.append(
                (state, submission_id)
            )
            with (
                patch.object(
                    relay_module,
                    "windows_drive_path",
                    side_effect=lambda path: home if path == native_home else executable,
                ),
                patch.dict(os.environ, {"WSLENV": "OTHER/u:CODEX_HOME/p"}),
            ):
                try:
                    await app.connect()
                    events = [
                        item async for item in app.run_turn("thread", '继续：中文 😀 "quoted"')
                    ]
                finally:
                    await app.close()
            self.assertEqual(events, [("queued", None)])
            self.assertEqual(states, [("submitting", None), ("accepted", "queued-id")])
            records = [
                json.loads(line) for line in (home / "requests.jsonl").read_text().splitlines()
            ]
            self.assertEqual(records[0], {"home": native_home, "wslenv": "OTHER/u:CODEX_HOME/w"})
            self.assertEqual(
                [record["method"] for record in records[1:]],
                ["initialize", "initialized", "thread/queue/add"],
            )
            params = records[-1]["params"]
            self.assertEqual(params["input"], [{"type": "text", "text": '继续：中文 😀 "quoted"'}])
            self.assertEqual(len(params["clientUserMessageId"]), 32)
            self.assertIsNone(app._process)

    async def test_bridge_rejects_missing_descriptor_and_mismatched_home_before_starting(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            with patch.object(relay_module.asyncio, "create_subprocess_exec") as start:
                with self.assertRaisesRegex(relay_module.AppServerError, "descriptor"):
                    await relay_module.WindowsAppServer(home).connect()
                (home / "wsl-bridge.json").write_text(
                    json.dumps(
                        {"codexHome": r"C:\another-home", "codexExecutable": r"C:\codex.exe"}
                    )
                )
                with self.assertRaisesRegex(relay_module.AppServerError, "different Codex home"):
                    await relay_module.WindowsAppServer(home).connect()
                start.assert_not_called()
