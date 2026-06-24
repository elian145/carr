"""Split sell_step1_pickers.dart into trim catalog UI and list pickers."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PICKERS = REPO / "lib/features/sell/sell_step1_pickers.dart"
FLOW = REPO / "lib/features/sell/sell_flow.dart"
STEP1 = REPO / "lib/features/sell/sell_step1.dart"
BUILD = REPO / "lib/features/sell/sell_step1_build.dart"
OUT = REPO / "lib/features/sell"

lines = PICKERS.read_text(encoding="utf-8").splitlines()

trim_start = find_line = next(
    i for i, line in enumerate(lines) if "_buildTrimCatalogSection" in line
)
lists_start = next(
    i for i, line in enumerate(lines) if "Future<String?> _pickFromList" in line
)

trim_block = "\n".join(lines[trim_start:lists_start]).rstrip()
lists_block = "\n".join(lines[lists_start:-1]).rstrip()

(OUT / "sell_step1_pickers_trim.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    "mixin _SellStep1PickersTrim on _SellStep1Catalog {\n"
    f"{trim_block}\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "sell_step1_pickers.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    "mixin _SellStep1Pickers on _SellStep1PickersTrim {\n"
    f"{lists_block}\n"
    "}\n",
    encoding="utf-8",
)

flow = FLOW.read_text(encoding="utf-8")
if "sell_step1_pickers_trim.dart" not in flow:
    flow = flow.replace(
        "part 'sell_step1_pickers.dart';\n",
        "part 'sell_step1_pickers_trim.dart';\npart 'sell_step1_pickers.dart';\n",
    )
    FLOW.write_text(flow, encoding="utf-8")

step1 = STEP1.read_text(encoding="utf-8")
step1 = step1.replace(
    "_SellStep1Catalog, _SellStep1Pickers, _SellStep1Build",
    "_SellStep1Catalog, _SellStep1PickersTrim, _SellStep1Pickers, _SellStep1Build",
)
STEP1.write_text(step1, encoding="utf-8")

print("trim", len(trim_block.splitlines()), "lists", len(lists_block.splitlines()))
