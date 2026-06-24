"""Split home_more_filters_body_color.dart into fuel, body, and color sections."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/features/home/home_more_filters_body_color.dart"
FLOW = REPO / "lib/features/home/home_flow.dart"
PAGE = REPO / "lib/features/home/home_page.dart"
OUT = REPO / "lib/features/home"

lines = FILE.read_text(encoding="utf-8").splitlines()

body_line = next(i for i, line in enumerate(lines) if "!.bodyTypeLabel" in line)
color_line = next(i for i, line in enumerate(lines) if "!.colorLabel" in line)

def sized_box_before(marker: int) -> int:
    idx = marker
    while idx > 0:
        if (
            lines[idx].strip().startswith("SizedBox(")
            and idx + 2 < len(lines)
            and "fieldGap" in lines[idx + 2]
        ):
            return idx
        idx -= 1
    raise ValueError(f"no SizedBox before line {marker}")

body_split = sized_box_before(body_line)
color_split = sized_box_before(color_line)

fuel_block = "\n".join(lines[9:body_split]).rstrip()
body_block = "\n".join(lines[body_split:color_split]).rstrip()
color_block = "\n".join(lines[color_split:-3]).rstrip()

(OUT / "home_more_filters_fuel.dart").write_text(
    "part of 'home_flow.dart';\n\n"
    "mixin _HomePageMoreFiltersFuel on _HomePageMoreFiltersMileage {\n"
    "  List<Widget> _moreFiltersFuelWidgets(\n"
    "    BuildContext context,\n"
    "    void Function(void Function()) setStateDialog,\n"
    "    MoreFiltersDialogStyle style,\n"
    "  ) => [\n"
    f"{fuel_block}\n"
    "      ];\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "home_more_filters_body_type.dart").write_text(
    "part of 'home_flow.dart';\n\n"
    "mixin _HomePageMoreFiltersBodyType on _HomePageMoreFiltersFuel {\n"
    "  List<Widget> _moreFiltersBodyTypeWidgets(\n"
    "    BuildContext context,\n"
    "    void Function(void Function()) setStateDialog,\n"
    "    MoreFiltersDialogStyle style,\n"
    "  ) => [\n"
    f"{body_block}\n"
    "      ];\n"
    "}\n",
    encoding="utf-8",
)

(FILE).write_text(
    "part of 'home_flow.dart';\n\n"
    "mixin _HomePageMoreFiltersColor on _HomePageMoreFiltersBodyType {\n"
    "  List<Widget> _moreFiltersColorWidgets(\n"
    "    BuildContext context,\n"
    "    void Function(void Function()) setStateDialog,\n"
    "    MoreFiltersDialogStyle style,\n"
    "  ) => [\n"
    f"{color_block}\n"
    "      ];\n"
    "}\n\n"
    "mixin _HomePageMoreFiltersBodyColor on _HomePageMoreFiltersColor {\n"
    "  List<Widget> _moreFiltersBodyColorWidgets(\n"
    "    BuildContext context,\n"
    "    void Function(void Function()) setStateDialog,\n"
    "    MoreFiltersDialogStyle style,\n"
    "  ) => [\n"
    "        ..._moreFiltersFuelWidgets(context, setStateDialog, style),\n"
    "        ..._moreFiltersBodyTypeWidgets(context, setStateDialog, style),\n"
    "        ..._moreFiltersColorWidgets(context, setStateDialog, style),\n"
    "      ];\n"
    "}\n",
    encoding="utf-8",
)

flow = FLOW.read_text(encoding="utf-8")
for part in ("home_more_filters_fuel.dart", "home_more_filters_body_type.dart"):
    if f"part '{part}'" not in flow:
        flow = flow.replace(
            "part 'home_more_filters_body_color.dart';",
            f"part '{part}';\npart 'home_more_filters_body_color.dart';",
        )
FLOW.write_text(flow, encoding="utf-8")

page = PAGE.read_text(encoding="utf-8")
if "_HomePageMoreFiltersFuel" not in page:
    page = page.replace(
        "_HomePageMoreFiltersBodyColor,",
        "_HomePageMoreFiltersFuel,\n        _HomePageMoreFiltersBodyType,\n        _HomePageMoreFiltersColor,\n        _HomePageMoreFiltersBodyColor,",
    )
    PAGE.write_text(page, encoding="utf-8")

print("fuel", len(fuel_block.splitlines()), "body", len(body_block.splitlines()), "color", len(color_block.splitlines()))
