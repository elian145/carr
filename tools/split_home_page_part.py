#!/usr/bin/env python3
"""One-off: extract legacy HomePage into home_page_legacy.dart (part file)."""
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
main_path = REPO / "lib/legacy/main_legacy.dart"
part_path = REPO / "lib/legacy/home_page_legacy.dart"

lines = main_path.read_text(encoding="utf-8").splitlines(keepends=True)
# HomePage block: lines 4161-12345 (1-based)
start, end = 4160, 12345
home_body = "".join(lines[start:end])
part_path.write_text(
    "part of 'main_legacy.dart';\n\n" + home_body.lstrip(),
    encoding="utf-8",
)

insert_at = 88
before = lines[:insert_at]
if not any("part 'home_page_legacy.dart'" in ln for ln in before):
    before.append("part 'home_page_legacy.dart';\n")
before.extend(lines[insert_at:start])
main_path.write_text("".join(before) + "".join(lines[end:]), encoding="utf-8")
print(f"Wrote {part_path.name} ({len(home_body.splitlines())} lines)")
print(f"Updated {main_path.name} ({len(before) + len(lines) - end} lines)")
