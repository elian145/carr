#!/usr/bin/env python3
"""Run the same checks as CI locally (static + Flutter + backend smoke)."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _flutter() -> str:
    return shutil.which("flutter") or "flutter"


def run(cmd: list[str]) -> None:
    print("\n>>", " ".join(cmd))
    subprocess.check_call(cmd, cwd=ROOT)


def main() -> None:
    run([sys.executable, "scripts/verify_preflight.py", "--skip-host"])
    run([_flutter(), "analyze", "--no-fatal-infos"])
    run([_flutter(), "test", "--coverage"])
    run([sys.executable, "scripts/smoke_tests/test_backend_factory_smoke.py"])
    run([sys.executable, "scripts/smoke_tests/test_android_jdk_tools_smoke.py"])
    print("\nAll local CI checks passed.")


if __name__ == "__main__":
    main()
