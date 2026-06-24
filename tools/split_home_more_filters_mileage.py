"""Split home_more_filters_mileage.dart into range and chips sections."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
MILEAGE = REPO / "lib/features/home/home_more_filters_mileage.dart"
FLOW = REPO / "lib/features/home/home_flow.dart"
PAGE = REPO / "lib/features/home/home_page.dart"
OUT = REPO / "lib/features/home"

lines = MILEAGE.read_text(encoding="utf-8").splitlines()

title_line = next(
    i for i, line in enumerate(lines) if "!.titleStatus" in line
)
split_line = title_line
while split_line > 0:
    if (
        lines[split_line].strip().startswith("SizedBox(")
        and split_line + 2 < len(lines)
        and "fieldGap" in lines[split_line + 2]
    ):
        break
    split_line -= 1

range_block = "\n".join(lines[9:split_line]).rstrip()
chips_block = "\n".join(lines[split_line:-3]).rstrip()

(OUT / "home_more_filters_mileage_range.dart").write_text(
    "part of 'home_flow.dart';\n\n"
    "mixin _HomePageMoreFiltersMileageRange on _HomePageMoreFiltersYear {\n"
    "  List<Widget> _moreFiltersMileageRangeWidgets(\n"
    "    BuildContext context,\n"
    "    void Function(void Function()) setStateDialog,\n"
    "    MoreFiltersDialogStyle style,\n"
    "  ) => [\n"
    f"{range_block}\n"
    "      ];\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "home_more_filters_mileage.dart").write_text(
    "part of 'home_flow.dart';\n\n"
    "mixin _HomePageMoreFiltersMileageChips on _HomePageMoreFiltersMileageRange {\n"
    "  List<Widget> _moreFiltersMileageChipsWidgets(\n"
    "    BuildContext context,\n"
    "    void Function(void Function()) setStateDialog,\n"
    "    MoreFiltersDialogStyle style,\n"
    "  ) => [\n"
    f"{chips_block}\n"
    "      ];\n"
    "}\n\n"
    "mixin _HomePageMoreFiltersMileage on _HomePageMoreFiltersMileageChips {\n"
    "  List<Widget> _moreFiltersMileageWidgets(\n"
    "    BuildContext context,\n"
    "    void Function(void Function()) setStateDialog,\n"
    "    MoreFiltersDialogStyle style,\n"
    "  ) => [\n"
    "        ..._moreFiltersMileageRangeWidgets(context, setStateDialog, style),\n"
    "        ..._moreFiltersMileageChipsWidgets(context, setStateDialog, style),\n"
    "      ];\n"
    "}\n",
    encoding="utf-8",
)

flow = FLOW.read_text(encoding="utf-8")
if "home_more_filters_mileage_range.dart" not in flow:
    flow = flow.replace(
        "part 'home_more_filters_mileage.dart';",
        "part 'home_more_filters_mileage_range.dart';\npart 'home_more_filters_mileage.dart';",
    )
    FLOW.write_text(flow, encoding="utf-8")

page = PAGE.read_text(encoding="utf-8")
page = page.replace(
    "_HomePageMoreFiltersYear,\n        _HomePageMoreFiltersMileage,",
    "_HomePageMoreFiltersYear,\n        _HomePageMoreFiltersMileageRange,\n        _HomePageMoreFiltersMileageChips,\n        _HomePageMoreFiltersMileage,",
)
PAGE.write_text(page, encoding="utf-8")
print("range", len(range_block.splitlines()), "chips", len(chips_block.splitlines()))
