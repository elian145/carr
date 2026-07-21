#!/usr/bin/env python3
"""Ping production /health to reduce Render free-tier cold starts.

Render spins free web services down after ~15 minutes idle. Hitting /health
every ~10 minutes keeps the dyno warm for clients (and admin).

Examples:
  python scripts/keep_warm.py
  python scripts/keep_warm.py --host https://carr-5hrm.onrender.com --timeout 90
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request

DEFAULT_HOST = "https://carr-5hrm.onrender.com"


def main() -> int:
    p = argparse.ArgumentParser(description="Keep-warm ping for Render API")
    p.add_argument("--host", default=DEFAULT_HOST, help="API origin (no trailing path)")
    p.add_argument(
        "--timeout",
        type=float,
        default=90.0,
        help="HTTP timeout seconds (allow cold start)",
    )
    args = p.parse_args()
    base = args.host.rstrip("/")
    url = f"{base}/health"
    req = urllib.request.Request(url, method="GET", headers={"User-Agent": "carzo-keep-warm/1"})
    try:
        with urllib.request.urlopen(req, timeout=args.timeout) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            code = resp.getcode()
    except urllib.error.HTTPError as e:
        print(f"FAIL: {url} -> HTTP {e.code}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"FAIL: {url} -> {e}", file=sys.stderr)
        return 1

    if code != 200:
        print(f"FAIL: {url} -> HTTP {code}", file=sys.stderr)
        return 1
    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        print(f"FAIL: {url} non-JSON body", file=sys.stderr)
        return 1
    if data.get("status") != "ok":
        print(f"FAIL: {url} status={data.get('status')!r}", file=sys.stderr)
        return 1
    print(f"OK: {url} status=ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
