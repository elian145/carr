#!/usr/bin/env python3
"""
Standalone Roboflow HTTP caller. Run in a subprocess so the parent process
(eventlet/gunicorn) never touches the socket — avoids "maximum recursion depth
exceeded" from eventlet monkey-patching.

Stdin: JSON object with keys: url, params, data, timeout_connect, timeout_read
Stdout: Roboflow response JSON body, or {"error": "..."} on failure.
"""
import json
import sys

def main() -> None:
    try:
        inp = json.load(sys.stdin)
    except Exception as e:
        json.dump({"error": str(e)}, sys.stdout)
        sys.exit(1)
    url = inp.get("url")
    params = inp.get("params") or {}
    data = inp.get("data") or ""
    timeout_connect = int(inp.get("timeout_connect", 5))
    timeout_read = int(inp.get("timeout_read", 60))
    if not url:
        json.dump({"error": "missing url"}, sys.stdout)
        sys.exit(1)
    try:
        import requests
        r = requests.post(
            url,
            params=params,
            data=data,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            timeout=(timeout_connect, timeout_read),
        )
        r.raise_for_status()
        out = r.json() if r.content else {}
        print(json.dumps(out))
    except Exception as e:
        json.dump({"error": str(e)}, sys.stdout)
        sys.exit(1)

if __name__ == "__main__":
    main()
