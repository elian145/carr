#!/usr/bin/env python3
"""Report ApiService size and planned part boundaries (manual split).

Run:
  python tools/split_api_service.py

Automated extraction is not yet enabled — use line ranges below when splitting
into `lib/services/api/*` part files with `_ApiServiceAuth`-style helpers.
"""

from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SRC = REPO / "lib/services/api_service.dart"

BOUNDARIES = [
    ("api_http.dart", "Token + HTTP core", 46, 414),
    ("api_auth.dart", "Auth + profile + dealer admin", 416, 584),
    ("api_listings.dart", "Cars, favorites, saved searches", 586, 759),
    ("api_chat.dart", "Chat HTTP + attachments", 771, 878),
    ("api_admin.dart", "Reports, blocks, push admin", 880, 957),
]


def main() -> int:
    lines = SRC.read_text(encoding="utf-8").splitlines()
    print(f"api_service.dart: {len(lines)} lines")
    print("ApiException: lib/services/api_exception.dart")
    print("\nSuggested part boundaries (1-based line ranges):")
    for fname, label, start, end in BOUNDARIES:
        print(f"  {fname:20} {label:32} L{start}-{end} ({end - start + 1} lines)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
