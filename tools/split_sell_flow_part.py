#!/usr/bin/env python3
"""Extract legacy sell flow into sell_flow_legacy.dart (part file)."""
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
main_path = REPO / "lib/legacy/main_legacy.dart"
part_path = REPO / "lib/legacy/sell_flow_legacy.dart"

lines = main_path.read_text(encoding="utf-8").splitlines(keepends=True)
# Sell helpers + pages: lines 7928-17137 (1-based), ends before CarComparisonPage
start, end = 7927, 17137
body = "".join(lines[start:end])
part_path.write_text(
    "part of 'main_legacy.dart';\n\n" + body.lstrip(),
    encoding="utf-8",
)

# Insert part directive after home_page part line
insert_marker = "part 'home_page_legacy.dart';\n"
out: list[str] = []
inserted = False
for ln in lines[:start]:
    out.append(ln)
    if not inserted and ln == insert_marker:
        out.append("part 'sell_flow_legacy.dart';\n")
        inserted = True
if not inserted:
    raise SystemExit("Could not find home_page_legacy part directive")

main_path.write_text("".join(out) + "".join(lines[end:]), encoding="utf-8")
print(f"Wrote {part_path.name} ({len(body.splitlines())} lines)")
print(f"Updated {main_path.name} ({len(out) + len(lines) - end} lines)")
