#!/usr/bin/env python3
"""Extract CarDetailsPage into car_detail_legacy.dart (part file)."""
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
main_path = REPO / "lib/legacy/main_legacy.dart"
part_path = REPO / "lib/legacy/car_detail_legacy.dart"

lines = main_path.read_text(encoding="utf-8").splitlines(keepends=True)
# CarDetailsPage + _SpecItem: lines 5066-7927 (1-based)
start, end = 5065, 7927
body = "".join(lines[start:end])
part_path.write_text(
    "part of 'main_legacy.dart';\n\n" + body.lstrip(),
    encoding="utf-8",
)

sell_marker = "part 'sell_flow_legacy.dart';\n"
out: list[str] = []
inserted = False
for ln in lines[:start]:
    out.append(ln)
    if not inserted and ln == sell_marker:
        out.append("part 'car_detail_legacy.dart';\n")
        inserted = True
if not inserted:
    raise SystemExit("Could not find sell_flow_legacy part directive")

main_path.write_text("".join(out) + "".join(lines[end:]), encoding="utf-8")
print(f"Wrote {part_path.name} ({len(body.splitlines())} lines)")
print(f"Updated {main_path.name} ({len(out) + len(lines) - end} lines)")
