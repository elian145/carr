"""Split sell_step2_logic.dart into catalog + pickers mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
LOGIC = REPO / "lib/features/sell/sell_step2_logic.dart"
FLOW = REPO / "lib/features/sell/sell_flow.dart"
STEP2 = REPO / "lib/features/sell/sell_step2.dart"
BUILD = REPO / "lib/features/sell/sell_step2_build.dart"
OUT = REPO / "lib/features/sell"

lines = LOGIC.read_text(encoding="utf-8").splitlines()


def find(substr: str, start: int = 0) -> int:
    for i in range(start, len(lines)):
        if substr in lines[i]:
            return i
    raise ValueError(substr)


catalog_line = find("CatalogSellFieldOptions? _computeCatalogSellOpts")
pickers_line = find("Future<String?> _pickFromList(String title")

catalog_block = "\n".join(lines[catalog_line:pickers_line]).rstrip()
pickers_block = "\n".join(lines[pickers_line:-1]).rstrip()

(OUT / "sell_step2_catalog.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    "mixin _SellStep2Catalog on _SellStep2Fields {\n"
    f"{catalog_block}\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "sell_step2_pickers.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    "mixin _SellStep2Pickers on _SellStep2Catalog {\n"
    f"{pickers_block}\n"
    "}\n",
    encoding="utf-8",
)

LOGIC.unlink()

flow_text = FLOW.read_text(encoding="utf-8")
if "sell_step2_catalog.dart" not in flow_text:
    flow_text = flow_text.replace(
        "part 'sell_step2_logic.dart';\n",
        "part 'sell_step2_catalog.dart';\npart 'sell_step2_pickers.dart';\n",
    )
    FLOW.write_text(flow_text, encoding="utf-8")

step2_text = STEP2.read_text(encoding="utf-8")
step2_text = step2_text.replace(
    "with _SellStep2Logic, _SellStep2Build",
    "with _SellStep2Catalog, _SellStep2Pickers, _SellStep2Build",
)
STEP2.write_text(step2_text, encoding="utf-8")

build_text = BUILD.read_text(encoding="utf-8")
build_text = build_text.replace(
    "mixin _SellStep2Build on _SellStep2Logic",
    "mixin _SellStep2Build on _SellStep2Pickers",
)
BUILD.write_text(build_text, encoding="utf-8")

print("catalog", len(catalog_block.splitlines()), "pickers", len(pickers_block.splitlines()))
