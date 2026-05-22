#!/usr/bin/env python3
"""Restore legacy part files from a known-good git revision."""
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
REF = "f353456:lib/legacy/main_legacy.dart"

old = subprocess.check_output(["git", "show", REF], cwd=REPO).decode("utf-8", errors="replace")
lines = old.splitlines(keepends=True)

# 1-based inclusive ranges from f353456/main_legacy.dart
RANGES = {
    "comparison_legacy.dart": (5068, 7597),
    "auth_pages_legacy.dart": (7598, 8833),
    "account_pages_legacy.dart": (8834, len(lines)),
}

legacy = REPO / "lib/legacy"
for name, (start, end) in RANGES.items():
    body = "".join(lines[start - 1 : end])
    (legacy / name).write_text(
        f"part of 'main_legacy.dart';\n\n{body.lstrip()}",
        encoding="utf-8",
    )
    print(f"{name}: {end - start + 1} lines")
