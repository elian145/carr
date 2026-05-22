#!/usr/bin/env python3
"""Rebuild main_legacy.dart shell from git, referencing external part files."""
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
REF = "f353456:lib/legacy/main_legacy.dart"

PARTS = [
    "home_page_legacy.dart",
    "saved_searches_legacy.dart",
    "car_detail_legacy.dart",
    "sell_flow_legacy.dart",
    "comparison_legacy.dart",
    "auth_pages_legacy.dart",
    "account_pages_legacy.dart",
]

# Ranges to REMOVE from f353456 (1-based inclusive) — moved into part files.
REMOVE_RANGES = [
    (4161, 12345),  # home
    (5066, 7927),  # car detail (+ _SpecItem)
    (7928, 17137),  # sell flow
    (4165, 5067),  # saved searches (overlaps home end — apply after merge)
    (5068, 7597),  # comparison
    (7598, 8833),  # auth pages
    (8834, 10_000_000),  # account pages to EOF
]

old = subprocess.check_output(["git", "show", REF], cwd=REPO).decode("utf-8", errors="replace")
lines = old.splitlines(keepends=True)

# Merge overlapping remove ranges
REMOVE_RANGES.sort()
merged: list[tuple[int, int]] = []
for a, b in REMOVE_RANGES:
    if merged and a <= merged[-1][1] + 1:
        merged[-1] = (merged[-1][0], max(merged[-1][1], b))
    else:
        merged.append((a, b))

remove = set()
for a, b in merged:
    for i in range(a - 1, min(b, len(lines))):
        remove.add(i)

kept = [ln for i, ln in enumerate(lines) if i not in remove]

# Insert part directives after imports
out: list[str] = []
inserted = False
for ln in kept:
    out.append(ln)
    if not inserted and ln.strip() == "import '../widgets/edge_swipe_back.dart';":
        for p in PARTS:
            out.append(f"part '{p}';\n")
        inserted = True

if not inserted:
    raise SystemExit("import anchor not found")

main_path = REPO / "lib/legacy/main_legacy.dart"
main_path.write_text("".join(out), encoding="utf-8")
print(f"Rebuilt {main_path.name}: {len(out)} lines")
