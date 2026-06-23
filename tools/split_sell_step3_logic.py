"""Split sell_step3_logic.dart into catalog + pickers mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
LOGIC = REPO / "lib/features/sell/sell_step3_logic.dart"
FLOW = REPO / "lib/features/sell/sell_flow.dart"
STEP3 = REPO / "lib/features/sell/sell_step3.dart"
BUILD = REPO / "lib/features/sell/sell_step3_build.dart"
OUT = REPO / "lib/features/sell"

lines = LOGIC.read_text(encoding="utf-8").splitlines()


def find(substr: str, start: int = 0) -> int:
    for i in range(start, len(lines)):
        if substr in lines[i]:
            return i
    raise ValueError(substr)


catalog_line = find("void initState()")
if catalog_line > 0 and lines[catalog_line - 1].strip() == "@override":
    catalog_line -= 1
pickers_line = find("Future<String?> _pickFromList(String title")

catalog_block = "\n".join(lines[catalog_line:pickers_line]).rstrip()
pickers_block = "\n".join(lines[pickers_line:-1]).rstrip()

(OUT / "sell_step3_catalog.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    "mixin _SellStep3Catalog on _SellStep3Fields {\n"
    f"{catalog_block}\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "sell_step3_pickers.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    "mixin _SellStep3Pickers on _SellStep3Catalog {\n"
    f"{pickers_block}\n"
    "}\n",
    encoding="utf-8",
)

LOGIC.unlink()

flow_text = FLOW.read_text(encoding="utf-8")
if "sell_step3_catalog.dart" not in flow_text:
    flow_text = flow_text.replace(
        "part 'sell_step3_logic.dart';\n",
        "part 'sell_step3_catalog.dart';\npart 'sell_step3_pickers.dart';\n",
    )
    if "sell_currency_convert.dart" not in flow_text:
        flow_text = flow_text.replace(
            "import 'sell_brand_slug.dart';\n",
            "import 'sell_brand_slug.dart';\nimport 'sell_currency_convert.dart';\n",
        )
    FLOW.write_text(flow_text, encoding="utf-8")

step3_text = STEP3.read_text(encoding="utf-8")
step3_text = step3_text.replace(
    "_SellStep3Fields, _SellStep3Logic, _SellStep3Build",
    "_SellStep3Fields, _SellStep3Catalog, _SellStep3Pickers, _SellStep3Build",
)
STEP3.write_text(step3_text, encoding="utf-8")

build_text = BUILD.read_text(encoding="utf-8")
build_text = build_text.replace(
    "mixin _SellStep3Build on _SellStep3Logic",
    "mixin _SellStep3Build on _SellStep3Pickers",
)
build_text = build_text.replace("_convertCurrency(", "convertSellListingPrice(")
BUILD.write_text(build_text, encoding="utf-8")

print("catalog", len(catalog_block.splitlines()), "pickers", len(pickers_block.splitlines()))
