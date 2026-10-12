import base64
import contextlib
import io
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import totp as main


class TwoFactorTests(unittest.TestCase):
    key = base64.b32encode(b"12345678901234567890").decode()

    def test_rfc4226_hotp_vectors(self):
        expected = [
            "755224",
            "287082",
            "359152",
            "969429",
            "338314",
            "254676",
            "287922",
            "162583",
            "399871",
            "520489",
        ]
        for counter, code in enumerate(expected):
            self.assertEqual(main.hotp(self.key, counter), code)

    def test_rfc6238_totp_vectors(self):
        for timestamp, code in [
            (59, "94287082"),
            (1111111109, "07081804"),
            (1111111111, "14050471"),
            (1234567890, "89005924"),
            (2000000000, "69279037"),
            (20000000000, "65353130"),
        ]:
            self.assertEqual(main.hotp(self.key, timestamp // 30, digits=8), code)

    def test_cli_reads_xdg_key_and_copies_code(self):
        with tempfile.TemporaryDirectory() as directory:
            keys = Path(directory) / "2fa/keys"
            keys.mkdir(parents=True)
            (keys / "example").write_text(self.key.lower() + "\n")
            output = io.StringIO()
            with (
                patch.dict(os.environ, {"XDG_CONFIG_HOME": directory}),
                patch("totp.time.time", return_value=59),
                patch("totp.copy_code", return_value=True) as copy,
                contextlib.redirect_stdout(output),
            ):
                self.assertEqual(main.main(["example"]), 0)
                copy.assert_called_once_with("287082")
                self.assertEqual(output.getvalue(), "287082\n")

    def test_invalid_key_is_not_printed(self):
        with tempfile.TemporaryDirectory() as directory:
            keys = Path(directory) / "2fa/keys"
            keys.mkdir(parents=True)
            (keys / "invalid").write_text("invalid-secret!")
            output, errors = io.StringIO(), io.StringIO()
            with (
                patch.dict(os.environ, {"XDG_CONFIG_HOME": directory}),
                contextlib.redirect_stdout(output),
                contextlib.redirect_stderr(errors),
            ):
                self.assertEqual(main.main(["invalid"]), 1)
                self.assertEqual(output.getvalue(), "")
                self.assertNotIn("invalid-secret!", errors.getvalue())

    def test_path_traversal_is_rejected(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
            main.main(["../key"])
        self.assertEqual(error.exception.code, 2)

    def test_clipboard_failure_does_not_fail_generation(self):
        with tempfile.TemporaryDirectory() as directory:
            keys = Path(directory) / "2fa/keys"
            keys.mkdir(parents=True)
            (keys / "example").write_text(self.key)
            with (
                patch.dict(os.environ, {"XDG_CONFIG_HOME": directory}),
                patch("totp.copy_code", return_value=False),
                contextlib.redirect_stdout(io.StringIO()),
                contextlib.redirect_stderr(io.StringIO()),
            ):
                self.assertEqual(main.main(["example"]), 0)


if __name__ == "__main__":
    unittest.main()
