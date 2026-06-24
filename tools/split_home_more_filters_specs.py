"""Split home_more_filters_specs.dart into drive, engine, and plate sections."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/features/home/home_more_filters_specs.dart"
FLOW = REPO / "lib/features/home/home_flow.dart"
PAGE = REPO / "lib/features/home/home_page.dart"
OUT = REPO / "lib/features/home"

lines = FILE.read_text(encoding="utf-8").splitlines()

cylinder_line = next(i for i, line in enumerate(lines) if "!.cylinderCount" in line)
plate_line = next(i for i, line in enumerate(lines) if "'Plate type'" in line)


def sized_box_before(marker: int) -> int:
    idx = marker
    while idx > 0:
        if lines[idx].strip().startswith("SizedBox(") and "height: 12" in lines[idx]:
            return idx
        idx -= 1
    raise ValueError(f"no SizedBox before line {marker}")


drive_split = sized_box_before(cylinder_line)
plate_split = sized_box_before(plate_line)

drive_block = "\n".join(lines[9:drive_split]).rstrip()
engine_block = "\n".join(lines[drive_split:plate_split]).rstrip()
plate_block = "\n".join(lines[plate_split:-3]).rstrip()

(OUT / "home_more_filters_specs_drive.dart").write_text(
    "part of 'home_flow.dart';\n\n"
    "mixin _HomePageMoreFiltersSpecsDrive on _HomePageMoreFiltersMid {\n"
    "  List<Widget> _moreFiltersSpecsDriveWidgets(\n"
    "    BuildContext context,\n"
    "    void Function(void Function()) setStateDialog,\n"
    "    MoreFiltersDialogStyle style,\n"
    "  ) => [\n"
    f"{drive_block}\n"
    "      ];\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "home_more_filters_specs_engine.dart").write_text(
    "part of 'home_flow.dart';\n\n"
    "mixin _HomePageMoreFiltersSpecsEngine on _HomePageMoreFiltersSpecsDrive {\n"
    "  List<Widget> _moreFiltersSpecsEngineWidgets(\n"
    "    BuildContext context,\n"
    "    void Function(void Function()) setStateDialog,\n"
    "    MoreFiltersDialogStyle style,\n"
    "  ) => [\n"
    f"{engine_block}\n"
    "      ];\n"
    "}\n",
    encoding="utf-8",
)

(FILE).write_text(
    "part of 'home_flow.dart';\n\n"
    "mixin _HomePageMoreFiltersSpecsPlate on _HomePageMoreFiltersSpecsEngine {\n"
    "  List<Widget> _moreFiltersSpecsPlateWidgets(\n"
    "    BuildContext context,\n"
    "    void Function(void Function()) setStateDialog,\n"
    "    MoreFiltersDialogStyle style,\n"
    "  ) => [\n"
    f"{plate_block}\n"
    "      ];\n"
    "}\n\n"
    "mixin _HomePageMoreFiltersSpecs on _HomePageMoreFiltersSpecsPlate {\n"
    "  List<Widget> _moreFiltersSpecsWidgets(\n"
    "    BuildContext context,\n"
    "    void Function(void Function()) setStateDialog,\n"
    "    MoreFiltersDialogStyle style,\n"
    "  ) => [\n"
    "        ..._moreFiltersSpecsDriveWidgets(context, setStateDialog, style),\n"
    "        ..._moreFiltersSpecsEngineWidgets(context, setStateDialog, style),\n"
    "        ..._moreFiltersSpecsPlateWidgets(context, setStateDialog, style),\n"
    "      ];\n"
    "}\n",
    encoding="utf-8",
)

flow = FLOW.read_text(encoding="utf-8")
for part in (
    "part 'home_more_filters_specs_drive.dart';\n",
    "part 'home_more_filters_specs_engine.dart';\n",
):
    if part not in flow:
        flow = flow.replace(
            "part 'home_more_filters_specs.dart';\n",
            part + "part 'home_more_filters_specs.dart';\n",
        )
FLOW.write_text(flow, encoding="utf-8")

page = PAGE.read_text(encoding="utf-8")
if "_HomePageMoreFiltersSpecsDrive" not in page:
    page = page.replace(
        "        _HomePageMoreFiltersMid,\n"
        "        _HomePageMoreFiltersSpecs,\n",
        "        _HomePageMoreFiltersMid,\n"
        "        _HomePageMoreFiltersSpecsDrive,\n"
        "        _HomePageMoreFiltersSpecsEngine,\n"
        "        _HomePageMoreFiltersSpecsPlate,\n"
        "        _HomePageMoreFiltersSpecs,\n",
    )
PAGE.write_text(page, encoding="utf-8")

print("Split home_more_filters_specs -> drive, engine, plate")
