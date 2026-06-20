#!/usr/bin/env python3
"""Add logNonFatal to empty or swallowing catch blocks (non-UI behavior change)."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "lib"
IMPORT_LINE = "import '../shared/debug/app_log.dart';"
IMPORT_LINE_DEPTH = {
    0: "import 'shared/debug/app_log.dart';",
    1: "import '../shared/debug/app_log.dart';",
    2: "import '../../shared/debug/app_log.dart';",
}


def import_for(path: Path) -> str:
    rel = path.relative_to(LIB)
    depth = len(rel.parts) - 1
    if depth in IMPORT_LINE_DEPTH:
        return IMPORT_LINE_DEPTH[depth]
    return "../" * depth + "shared/debug/app_log.dart"


def ensure_import(text: str, path: Path) -> str:
    if "app_log.dart" in text or path.parts[1:2] == ("legacy",):
        return text
    imp = f"import '{import_for(path)}';"
    if imp in text:
        return text
    lines = text.splitlines(keepends=True)
    insert_at = 0
    for i, line in enumerate(lines):
        if line.startswith("import "):
            insert_at = i + 1
    lines.insert(insert_at, imp + "\n")
    return "".join(lines)


def patch_catches(text: str) -> str:
    text = re.sub(
        r"catch\s\(_\)\s\{\s*\}",
        "catch (e, st) { logNonFatal(e, st); }",
        text,
    )
    text = re.sub(
        r"catch\s\(_\)\s\{",
        "catch (e, st) { logNonFatal(e, st); ",
        text,
    )
    return text


def main() -> int:
    changed = 0
    for path in sorted(LIB.rglob("*.dart")):
        if "legacy" in path.parts:
            # legacy part library: app_log already imported from main_legacy.dart
            if path.name != "main_legacy.dart" and "legacy" in path.parts:
                original = path.read_text(encoding="utf-8")
                updated = patch_catches(original)
                if updated != original:
                    path.write_text(updated, encoding="utf-8")
                    changed += 1
                continue
        original = path.read_text(encoding="utf-8")
        if "catch (_)" not in original and "catch (_)" not in original.replace("catch (_)", ""):
            if "catch (_)" not in original:
                continue
        updated = patch_catches(original)
        if "logNonFatal" in updated and path.parts[1:2] != ("legacy",):
            updated = ensure_import(updated, path)
        if updated != original:
            path.write_text(updated, encoding="utf-8")
            changed += 1
            print(path.relative_to(ROOT))
    print(f"Updated {changed} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
