#!/usr/bin/env python3
"""Extract a line range from main_legacy.dart into a new part file."""
import argparse
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
MAIN = REPO / "lib/legacy/main_legacy.dart"


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("part_name", help="e.g. saved_searches_legacy.dart")
    p.add_argument("start_line", type=int, help="1-based inclusive start")
    p.add_argument("end_line", type=int, help="1-based inclusive end")
    args = p.parse_args()

    lines = MAIN.read_text(encoding="utf-8").splitlines(keepends=True)
    start, end = args.start_line - 1, args.end_line
    if start < 0 or end > len(lines) or start >= end:
        raise SystemExit(f"Invalid range {args.start_line}-{args.end_line} (file has {len(lines)} lines)")

    part_path = REPO / "lib/legacy" / args.part_name
    body = "".join(lines[start:end])
    part_path.write_text(
        f"part of 'main_legacy.dart';\n\n{body.lstrip()}",
        encoding="utf-8",
    )

    directive = f"part '{args.part_name}';\n"
    if any(ln == directive for ln in lines):
        raise SystemExit(f"Part {args.part_name} already registered")

    part_line_idxs = [
        i for i in range(start) if lines[i].startswith("part '") and lines[i].rstrip().endswith(".dart';")
    ]
    if not part_line_idxs:
        raise SystemExit("Could not find part directives block")
    insert_at = part_line_idxs[-1] + 1
    new_main = lines[:insert_at] + [directive] + lines[insert_at:start] + lines[end:]
    MAIN.write_text("".join(new_main), encoding="utf-8")
    print(
        f"Wrote {args.part_name} ({end - start} lines), "
        f"main now {len(new_main)} lines"
    )


if __name__ == "__main__":
    main()
