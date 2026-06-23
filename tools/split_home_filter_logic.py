"""Split home_filter_logic.dart into catalog, persist, and chips mixins."""
from __future__ import annotations

import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
LOGIC = REPO / "lib/features/home/home_filter_logic.dart"
FLOW = REPO / "lib/features/home/home_flow.dart"
HOME = REPO / "lib/features/home"


def load_body() -> list[str]:
    lines = LOGIC.read_text(encoding="utf-8").splitlines()
    if len(lines) > 100 and "mixin _HomePageFilterLogic" in lines[2]:
        start = 3
        end = len(lines) - 1 if lines[-1].strip() == "}" else len(lines)
        return lines[start:end]
    raw = subprocess.check_output(
        ["git", "show", "HEAD:lib/features/home/home_filter_logic.dart"],
        cwd=REPO,
        text=True,
        encoding="utf-8",
    )
    glines = raw.splitlines()
    start = next(
        i
        for i, ln in enumerate(glines)
        if ln.strip().startswith("mixin _HomePageFilterLogic")
    ) + 1
    end = len(glines) - 1 if glines[-1].strip() == "}" else len(glines)
    return glines[start:end]


def find(lines: list[str], substr: str) -> int:
    for i, ln in enumerate(lines):
        if substr in ln:
            return i
    raise ValueError(substr)


lines = load_body()
persist_start = find(lines, "void _resetAllFiltersInMemory()")
catalog_tail_start = find(lines, "void clearFiltersOnVehicleChange()")
chips_start = find(lines, "bool _hasActiveFilters()")

catalog_block = "\n".join(lines[:persist_start] + lines[catalog_tail_start:chips_start]).rstrip()
persist_block = "\n".join(lines[persist_start:catalog_tail_start]).rstrip()
chips_block = "\n".join(lines[chips_start:]).rstrip()

(HOME / "home_filter_catalog.dart").write_text(
    "part of 'home_flow.dart';\n\n"
    "mixin _HomePageFilterCatalog on _HomePageFetch {\n"
    f"{catalog_block}\n"
    "}\n",
    encoding="utf-8",
)
(HOME / "home_filter_persist.dart").write_text(
    "part of 'home_flow.dart';\n\n"
    "mixin _HomePageFilterPersist on _HomePageFilterCatalog {\n"
    f"{persist_block}\n"
    "}\n",
    encoding="utf-8",
)
LOGIC.write_text(
    "part of 'home_flow.dart';\n\n"
    "mixin _HomePageFilterLogic on _HomePageFilterPersist {\n"
    f"{chips_block}\n"
    "}\n",
    encoding="utf-8",
)

flow = FLOW.read_text(encoding="utf-8")
for part in ("home_filter_catalog.dart", "home_filter_persist.dart"):
    if f"part '{part}'" not in flow:
        flow = flow.replace(
            "part 'home_filter_logic.dart';",
            f"part '{part}';\npart 'home_filter_logic.dart';",
        )
FLOW.write_text(flow, encoding="utf-8")

print(
    "catalog",
    len(catalog_block.splitlines()),
    "persist",
    len(persist_block.splitlines()),
    "chips",
    len(chips_block.splitlines()),
)
