#!/usr/bin/env python3
"""Print Firebase service account JSON as one line for Render FIREBASE_SERVICE_ACCOUNT."""
from __future__ import annotations

import json
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: python scripts/format_firebase_service_account_json.py path/to/service-account.json")
        return 1
    path = Path(sys.argv[1])
    data = json.loads(path.read_text(encoding="utf-8"))
    print(json.dumps(data, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
