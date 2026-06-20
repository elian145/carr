#!/usr/bin/env python3
"""Rename DropdownButtonFormField value: to initialValue: (Flutter 3.35+)."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = [
    ROOT / "lib/pages/admin_reports_page.dart",
    ROOT / "lib/pages/edit_listing_page.dart",
    ROOT / "lib/pages/sell_page.dart",
]


def patch(text: str) -> str:
    out: list[str] = []
    depth = 0
    in_dbf = False
    for line in text.splitlines(keepends=True):
        if "DropdownButtonFormField" in line:
            in_dbf = True
            depth = line.count("(") - line.count(")")
        elif in_dbf:
            depth += line.count("(") - line.count(")")
            if (
                re.match(r"(\s+)value:", line)
                and "DropdownMenuItem" not in line
                and "items:" not in out[-1] if out else True
            ):
                # Only rename the form field's own value param (before items:).
                if not any("items:" in prev for prev in out[-8:]):
                    line = re.sub(r"^(\s+)value:", r"\1initialValue:", line, count=1)
            if depth <= 0:
                in_dbf = False
        out.append(line)
    return "".join(out)


def main() -> int:
    for path in FILES:
        original = path.read_text(encoding="utf-8")
        updated = patch(original)
        if updated != original:
            path.write_text(updated, encoding="utf-8")
            print(path.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
