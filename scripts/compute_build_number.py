#!/usr/bin/env python3
"""Compute a monotonic, store-valid release build number.

Apple CFBundleVersion: digits only here, <= 18 chars, must increase per upload.
Android versionCode: integer <= 2_100_000_000 (we stay below that for both).

number = BUILD_NUMBER_OFFSET + <CI sequential build counter>
Counter source (first set wins): PROJECT_BUILD_NUMBER, CM_BUILD_NUMBER.
It is never derived from CM_BUILD_ID (a 24-char hex id: letters are invalid and
truncating it is not monotonic). The result is never below the pubspec build
number. Prints the integer on stdout; diagnostics go to stderr.

Owner: set BUILD_NUMBER_OFFSET above the highest build number already uploaded
to App Store Connect / Play (see docs/OWNER_ACTIONS.md).
"""
from __future__ import annotations

import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
MAX_CODE = 2_100_000_000


def pubspec_build_number(path: str | None = None) -> int:
    path = path or os.path.join(ROOT, "pubspec.yaml")
    with open(path, encoding="utf-8") as fh:
        m = re.search(r"^version:\s*[\w.\-]+\+(\d+)\s*$", fh.read(), re.M)
    if not m:
        raise ValueError("pubspec.yaml version must look like x.y.z+N")
    return int(m.group(1))


def compute(env: dict[str, str], floor: int) -> int:
    raw = ""
    for key in ("PROJECT_BUILD_NUMBER", "CM_BUILD_NUMBER"):
        raw = (env.get(key) or "").strip()
        if raw:
            break
    if not raw.isdigit():
        raise ValueError("no numeric PROJECT_BUILD_NUMBER/CM_BUILD_NUMBER available")
    offset_raw = (env.get("BUILD_NUMBER_OFFSET") or "0").strip()
    if not offset_raw.isdigit():
        raise ValueError("BUILD_NUMBER_OFFSET must be a non-negative integer")
    number = max(floor, int(offset_raw) + int(raw))
    if number > MAX_CODE:
        raise ValueError(f"build number {number} exceeds {MAX_CODE}")
    return number


def main() -> int:
    try:
        print(compute(dict(os.environ), pubspec_build_number()))
    except (ValueError, OSError) as exc:
        print(f"compute_build_number: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
