import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from audio_transcribe import cli


class TranscribeCliTests(unittest.TestCase):
    def test_transcribes_all_segments_with_requested_options(self):
        with tempfile.TemporaryDirectory() as directory:
            audio = Path(directory) / "录音.m4a"
            audio.touch()
            cache = Path(directory) / "models"
            output = Path(directory) / "文字.txt"
            calls = {}

            class FakeModel:
                def __init__(self, model, **kwargs):
                    calls["model"] = model
                    calls["init"] = kwargs

                def transcribe(self, path, **kwargs):
                    calls["path"] = path
                    calls["transcribe"] = kwargs
                    return iter(
                        [
                            SimpleNamespace(start=0, end=1.25, text=" 你好 "),
                            SimpleNamespace(start=1.25, end=2.5, text=" 世界 "),
                        ]
                    ), SimpleNamespace(language="zh")

            args = cli.build_parser().parse_args(
                [
                    str(audio),
                    "-o",
                    str(output),
                    "--model-cache",
                    str(cache),
                    "--language",
                    "zh",
                    "--timestamps",
                    "--vad",
                ]
            )
            stdout = io.StringIO()
            stderr = io.StringIO()
            with patch.dict(
                sys.modules, {"faster_whisper": SimpleNamespace(WhisperModel=FakeModel)}
            ):
                with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                    self.assertEqual(cli.run(args), 0)

            self.assertEqual(stdout.getvalue(), "")
            self.assertEqual(
                output.read_text(encoding="utf-8"),
                "[00:00:00.000 -> 00:00:01.250] 你好\n[00:00:01.250 -> 00:00:02.500] 世界\n",
            )
            self.assertEqual(calls["model"], "large-v3")
            self.assertEqual(calls["init"]["download_root"], str(cache))
            self.assertEqual(calls["transcribe"]["language"], "zh")
            self.assertTrue(calls["transcribe"]["vad_filter"])

    def test_missing_audio_fails_before_loading_model(self):
        args = cli.build_parser().parse_args(["missing.wav"])
        with self.assertRaisesRegex(ValueError, "audio file does not exist"):
            cli.run(args)


if __name__ == "__main__":
    unittest.main()
