"""Split home_filter_bar.dart into brand picker and filter row mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/features/home/home_filter_bar.dart"
FLOW = REPO / "lib/features/home/home_flow.dart"
PAGE = REPO / "lib/features/home/home_page.dart"
OUT = REPO / "lib/features/home"

lines = FILE.read_text(encoding="utf-8").splitlines()
row_start = next(i for i, line in enumerate(lines) if line.strip().startswith("Widget _buildHomeVehicleFilterRow"))

brand_block = "\n".join(lines[3:row_start]).rstrip()
row_block = "\n".join(lines[row_start:-1]).rstrip()

(OUT / "home_filter_bar_brand.dart").write_text(
    "part of 'home_flow.dart';\n\n"
    "mixin _HomePageFilterBarBrand on _HomePageFilterLogic {\n"
    f"{brand_block}\n"
    "}\n",
    encoding="utf-8",
)

(FILE).write_text(
    "part of 'home_flow.dart';\n\n"
    "mixin _HomePageFilterBar on _HomePageFilterBarBrand {\n"
    f"{row_block}\n"
    "}\n",
    encoding="utf-8",
)

flow = FLOW.read_text(encoding="utf-8")
if "home_filter_bar_brand.dart" not in flow:
    flow = flow.replace(
        "part 'home_filter_bar.dart';\n",
        "part 'home_filter_bar_brand.dart';\npart 'home_filter_bar.dart';\n",
    )
    FLOW.write_text(flow, encoding="utf-8")

page = PAGE.read_text(encoding="utf-8")
if "_HomePageFilterBarBrand" not in page:
    page = page.replace(
        "        _HomePageFilterBar,\n",
        "        _HomePageFilterBarBrand,\n        _HomePageFilterBar,\n",
    )
    PAGE.write_text(page, encoding="utf-8")

print("Split home_filter_bar -> brand + row")
