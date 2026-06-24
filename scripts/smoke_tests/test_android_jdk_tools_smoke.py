#!/usr/bin/env python3
"""Smoke tests for scripts/android_jdk_tools.py (no keystore required)."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parents[1]
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

from android_jdk_tools import parse_sha256_lines  # noqa: E402


class AndroidJdkToolsSmokeTest(unittest.TestCase):
    def test_parse_sha256_lines(self):
        text = """
        Certificate fingerprints:
             SHA1: AB:CD
             SHA256: 9E:7A:AC:CF:0B:CE:7E:A3:0E:B9:9D:AF:DF:37:8E:1D:3E:6C:F6:C5:E8:C8:22:41:1E:53:F5:A5:72:40:97:E8
        """
        fps = parse_sha256_lines(text)
        self.assertEqual(len(fps), 1)
        self.assertTrue(fps[0].startswith("9E:7A:AC"))

    def test_parse_sha256_lines_empty(self):
        self.assertEqual(parse_sha256_lines("no fingerprints here"), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
