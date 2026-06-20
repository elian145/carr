#!/usr/bin/env python3
"""
Combined pre-publish checks: static repo preflight + optional deployed API smoke.

Examples:
  python scripts/verify_preflight.py
  python scripts/verify_preflight.py --host https://carr-5hrm.onrender.com
  python scripts/verify_preflight.py --host https://carr-5hrm.onrender.com --require-app-links
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _run(label: str, cmd: list[str]) -> None:
    print(f"\n== {label} ==")
    result = subprocess.run(cmd, cwd=ROOT)
    if result.returncode != 0:
        raise SystemExit(result.returncode)


def main() -> None:
    p = argparse.ArgumentParser(description="Static + deployed preflight for store upload")
    p.add_argument(
        "--host",
        default="https://carr-5hrm.onrender.com",
        help="API origin for deployed checks (no /api suffix)",
    )
    p.add_argument(
        "--skip-host",
        action="store_true",
        help="Only run static verify_publish_ready.py",
    )
    p.add_argument(
        "--require-app-links",
        action="store_true",
        help="Fail if Android/iOS well-known files are missing on --host",
    )
    p.add_argument(
        "--timeout",
        type=float,
        default=90.0,
        help="Per-request timeout for deployed checks",
    )
    args = p.parse_args()

    _run("Static publish preflight", [sys.executable, "scripts/verify_publish_ready.py"])

    if args.skip_host:
        print("\nAll preflight checks passed (host checks skipped).")
        return

    host_cmd = [
        sys.executable,
        "scripts/verify_production_host.py",
        "--host",
        args.host.strip(),
        "--timeout",
        str(args.timeout),
    ]
    if args.require_app_links:
        host_cmd.append("--require-app-links")

    _run(f"Deployed API ({args.host.strip()})", host_cmd)
    print("\nAll preflight checks passed.")


if __name__ == "__main__":
    main()
