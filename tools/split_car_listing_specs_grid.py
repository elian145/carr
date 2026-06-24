"""Split car_listing_specs_grid.dart into damage helpers, widgets, and build."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/features/listing/car_listing_specs_grid.dart"
OUT = REPO / "lib/features/listing"

lines = FILE.read_text(encoding="utf-8").splitlines()

damage_start = next(i for i, line in enumerate(lines) if line.startswith("List<String> listingDamageImageFullUrls"))
imports = "\n".join(lines[:damage_start]).rstrip()
build_start = next(i for i, line in enumerate(lines) if line.startswith("Widget buildCarListingSpecsGrid"))
doc_start = build_start
while doc_start > 0 and lines[doc_start - 1].startswith("///"):
    doc_start -= 1
open_brace = next(
    i for i in range(build_start, len(lines)) if lines[i].strip().endswith("{")
)
build_end = next(i for i in range(len(lines) - 1, build_start, -1) if lines[i].strip() == "}")
detail_start = next(i for i, line in enumerate(lines) if line.strip().startswith("Widget detailRowSpec"))
mileage_start = next(i for i, line in enumerate(lines) if line.strip().startswith("final String mileageVal"))

damage_block = "\n".join(lines[damage_start:build_start]).rstrip()

widgets_raw = "\n".join(lines[detail_start:mileage_start]).rstrip()
widgets_block = (
    widgets_raw.replace("  Widget detailRowSpec({", "Widget carListingSpecsDetailRow(\n  BuildContext context, {", 1)
    .replace("  Widget specCard(ListingSpecItem item) {", "Widget carListingSpecsCard(ListingSpecItem item) {", 1)
)

build_inner = "\n".join(lines[open_brace + 1 : detail_start] + lines[mileage_start:build_end]).rstrip()
build_inner = build_inner.replace("detailRowSpec(", "carListingSpecsDetailRow(context, ").replace(
    "specCard(", "carListingSpecsCard("
)
build_block = "\n".join(lines[doc_start : open_brace + 1]) + "\n" + build_inner + "\n}\n"

(FILE).write_text(
    imports
    + "\n\n"
    + "part 'car_listing_specs_grid_damage.dart';\n"
    + "part 'car_listing_specs_grid_widgets.dart';\n"
    + "part 'car_listing_specs_grid_build.dart';\n",
    encoding="utf-8",
)

(OUT / "car_listing_specs_grid_damage.dart").write_text(
    "part of 'car_listing_specs_grid.dart';\n\n" + damage_block + "\n",
    encoding="utf-8",
)

(OUT / "car_listing_specs_grid_widgets.dart").write_text(
    "part of 'car_listing_specs_grid.dart';\n\n" + widgets_block + "\n",
    encoding="utf-8",
)

(OUT / "car_listing_specs_grid_build.dart").write_text(
    "part of 'car_listing_specs_grid.dart';\n\n" + build_block + "\n",
    encoding="utf-8",
)

print("Split car_listing_specs_grid")
