#!/usr/bin/env python3
"""
Standalone OTPIQ HTTP caller. Run in a subprocess so the parent process
(eventlet/gunicorn) never touches the socket — avoids "maximum recursion depth
exceeded" from eventlet monkey-patching.

Stdin: JSON with keys: url, headers, json (body), timeout
Stdout: {"status": <int>, "body": <object|string>} or {"error": "..."}.
"""
from __future__ import annotations

import json
import sys


def main() -> None:
    try:
        inp = json.load(sys.stdin)
    except Exception as e:
        json.dump({"error": str(e)}, sys.stdout)
        sys.exit(1)

    url = inp.get("url")
    headers = inp.get("headers") or {}
    body = inp.get("json")
    timeout = float(inp.get("timeout", 15))
    if not url:
        json.dump({"error": "missing url"}, sys.stdout)
        sys.exit(1)

    try:
        import requests

        response = requests.post(url, json=body, headers=headers, timeout=timeout)
        try:
            parsed = response.json() if response.text else {}
        except Exception:
            parsed = response.text
        json.dump({"status": response.status_code, "body": parsed}, sys.stdout)
    except Exception as e:
        json.dump({"error": str(e)}, sys.stdout)
        sys.exit(1)


if __name__ == "__main__":
    main()
