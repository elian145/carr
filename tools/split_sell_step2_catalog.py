"""Split sell_step2_catalog.dart into options and hydrate mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
CATALOG = REPO / "lib/features/sell/sell_step2_catalog.dart"
FLOW = REPO / "lib/features/sell/sell_flow.dart"
STEP2 = REPO / "lib/features/sell/sell_step2.dart"
PICKERS = REPO / "lib/features/sell/sell_step2_pickers.dart"
OUT = REPO / "lib/features/sell"

lines = CATALOG.read_text(encoding="utf-8").splitlines()
split = next(i for i, line in enumerate(lines) if "_onlineMultiFromCarData" in line)

hydrate_block = "\n".join(lines[3:split]).rstrip()
options_block = "\n".join(lines[split:-1]).rstrip()

(OUT / "sell_step2_catalog_options.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    "mixin _SellStep2CatalogOptions on _SellStep2Fields {\n"
    f"{options_block}\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "sell_step2_catalog_hydrate.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    "mixin _SellStep2CatalogHydrate on _SellStep2CatalogOptions {\n"
    f"{hydrate_block}\n"
    "}\n",
    encoding="utf-8",
)

CATALOG.unlink()

flow = FLOW.read_text(encoding="utf-8")
flow = flow.replace(
    "part 'sell_step2_catalog.dart';",
    "part 'sell_step2_catalog_options.dart';\npart 'sell_step2_catalog_hydrate.dart';",
)
FLOW.write_text(flow, encoding="utf-8")

step2 = STEP2.read_text(encoding="utf-8")
step2 = step2.replace(
    "_SellStep2Catalog,",
    "_SellStep2CatalogOptions,\n        _SellStep2CatalogHydrate,",
)
STEP2.write_text(step2, encoding="utf-8")

pickers = PICKERS.read_text(encoding="utf-8")
pickers = pickers.replace(
    "mixin _SellStep2Pickers on _SellStep2Catalog",
    "mixin _SellStep2Pickers on _SellStep2CatalogHydrate",
)
PICKERS.write_text(pickers, encoding="utf-8")
print("hydrate", len(hydrate_block.splitlines()), "options", len(options_block.splitlines()))
