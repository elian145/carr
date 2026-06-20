#!/usr/bin/env python3
"""Replace Color.withOpacity with Color.withValues(alpha: ...)."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "lib"
PATTERN = re.compile(r"\.withOpacity\(([^)]+)\)")


def main() -> int:
    changed = 0
    for path in sorted(LIB.rglob("*.dart")):
        text = path.read_text(encoding="utf-8")
        if ".withOpacity(" not in text:
            continue
        updated = PATTERN.sub(r".withValues(alpha: \1)", text)
        if updated != text:
            path.write_text(updated, encoding="utf-8")
            changed += 1
            print(path.relative_to(ROOT))
    print(f"Updated {changed} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
