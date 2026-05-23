#!/usr/bin/env python3
"""Format Firebase service account JSON as one line for Render FIREBASE_SERVICE_ACCOUNT."""
from __future__ import annotations

import base64
import json
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(
            "Usage: python scripts/format_firebase_service_account_json.py "
            "path/to/service-account.json"
        )
        return 1
    path = Path(sys.argv[1])
    data = json.loads(path.read_text(encoding="utf-8"))
    one_line = json.dumps(data, separators=(",", ":"))
    out_file = Path("firebase-service-account-oneline.txt")
    out_file.write_text(one_line, encoding="utf-8")
    b64_file = Path("firebase-service-account-base64.txt")
    b64_file.write_text(base64.b64encode(one_line.encode("utf-8")).decode("ascii"), encoding="utf-8")
    print(f"Wrote one line ({len(one_line)} chars) to: {out_file.resolve()}")
    print(f"Wrote Base64 ({b64_file.stat().st_size} chars) to: {b64_file.resolve()}")
    print()
    print("Render (recommended): env FIREBASE_SERVICE_ACCOUNT_BASE64")
    print("  Paste contents of firebase-service-account-base64.txt (single line, no breaks).")
    print()
    print("PowerShell copy Base64 to clipboard:")
    print(f'  Get-Content "{b64_file.name}" -Raw | Set-Clipboard')
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
