#!/usr/bin/env python3
"""Run the same checks as CI locally (static + Flutter + backend smoke)."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(cmd: list[str]) -> None:
    print("\n>>", " ".join(cmd))
    subprocess.check_call(cmd, cwd=ROOT)


def main() -> None:
    run([sys.executable, "scripts/verify_preflight.py", "--skip-host"])
    run(["flutter", "analyze"])
    run(["flutter", "test"])
    run([sys.executable, "scripts/smoke_tests/test_backend_factory_smoke.py"])
    print("\nAll local CI checks passed.")


if __name__ == "__main__":
    main()
