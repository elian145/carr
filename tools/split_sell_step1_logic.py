"""Split sell_step1_logic.dart into catalog + pickers mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
LOGIC = REPO / "lib/features/sell/sell_step1_logic.dart"
FLOW = REPO / "lib/features/sell/sell_flow.dart"
STEP1 = REPO / "lib/features/sell/sell_step1.dart"
BUILD = REPO / "lib/features/sell/sell_step1_build.dart"
OUT = REPO / "lib/features/sell"

lines = LOGIC.read_text(encoding="utf-8").splitlines()


def find(substr: str, start: int = 0) -> int:
    for i in range(start, len(lines)):
        if substr in lines[i]:
            return i
    raise ValueError(substr)


hydrate_line = find("void _hydrateFromParentCarData()")
trim_line = find("Widget _buildTrimCatalogSection()")
getters_line = find("List<String> get brands => CarCatalog.brands")

catalog_block = "\n".join(lines[hydrate_line:trim_line] + lines[getters_line:-1]).rstrip()
pickers_block = "\n".join(lines[trim_line:getters_line]).rstrip()

catalog_block = catalog_block.replace("_brandSlug(", "sellBrandSlug(")

(OUT / "sell_step1_catalog.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    "mixin _SellStep1Catalog on _SellStep1Fields {\n"
    f"{catalog_block}\n"
    "}\n",
    encoding="utf-8",
)

pickers_block = pickers_block.replace("_brandSlug(", "sellBrandSlug(")
(OUT / "sell_step1_pickers.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    "mixin _SellStep1Pickers on _SellStep1Catalog {\n"
    f"{pickers_block}\n"
    "}\n",
    encoding="utf-8",
)

LOGIC.unlink()

flow_text = FLOW.read_text(encoding="utf-8")
if "sell_step1_catalog.dart" not in flow_text:
    flow_text = flow_text.replace(
        "part 'sell_step1_logic.dart';\n",
        "part 'sell_step1_catalog.dart';\npart 'sell_step1_pickers.dart';\n",
    )
    if "sell_brand_slug.dart" not in flow_text:
        flow_text = flow_text.replace(
            "import 'sell_listing_payload.dart';\n",
            "import 'sell_listing_payload.dart';\nimport 'sell_brand_slug.dart';\n",
        )
    FLOW.write_text(flow_text, encoding="utf-8")

step1_text = STEP1.read_text(encoding="utf-8")
step1_text = step1_text.replace(
    "with _SellStep1Logic, _SellStep1Build",
    "with _SellStep1Catalog, _SellStep1Pickers, _SellStep1Build",
)
STEP1.write_text(step1_text, encoding="utf-8")

build_text = BUILD.read_text(encoding="utf-8")
build_text = build_text.replace(
    "mixin _SellStep1Build on _SellStep1Logic",
    "mixin _SellStep1Build on _SellStep1Pickers",
)
build_text = build_text.replace("_brandSlug(", "sellBrandSlug(")
BUILD.write_text(build_text, encoding="utf-8")

print(
    "catalog",
    len(catalog_block.splitlines()),
    "pickers",
    len(pickers_block.splitlines()),
)
