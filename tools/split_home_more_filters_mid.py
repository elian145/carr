"""Split home_more_filters_mid into mileage and body/color sections."""
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
MID = REPO / "lib/features/home/home_more_filters_mid.dart"
FLOW = REPO / "lib/features/home/home_flow.dart"
lines = MID.read_text(encoding="utf-8").splitlines()

split_line = next(
    i
    for i, ln in enumerate(lines)
    if "bodyType_${selectedBodyType" in ln
)
# Include preceding SizedBox(fieldGap) block
while split_line > 0 and "SizedBox" not in lines[split_line - 1]:
    split_line -= 1
while split_line > 0 and "height:" not in lines[split_line - 1] and "SizedBox" not in lines[split_line - 1]:
    split_line -= 1
# Back up to SizedBox( line
split_line = next(i for i, ln in enumerate(lines) if i < split_line and ln.strip().startswith("SizedBox(") and i > 700)

mileage_widgets = "\n".join(lines[9:split_line])  # inside return [
body_widgets = "\n".join(lines[split_line:-2]).rstrip()
if body_widgets.endswith("];"):
    body_widgets = body_widgets[:-2].rstrip()

home = REPO / "lib/features/home"

(home / "home_more_filters_mileage.dart").write_text(
    "part of 'home_flow.dart';\n\n"
    "mixin _HomePageMoreFiltersMileage on _HomePageMoreFiltersYear {\n"
    "  List<Widget> _moreFiltersMileageWidgets(\n"
    "    BuildContext context,\n"
    "    void Function(void Function()) setStateDialog,\n"
    "    MoreFiltersDialogStyle style,\n"
    "  ) {\n"
    "    return <Widget>[\n"
    f"{mileage_widgets}\n"
    "    ];\n"
    "  }\n"
    "}\n",
    encoding="utf-8",
)

(home / "home_more_filters_body_color.dart").write_text(
    "part of 'home_flow.dart';\n\n"
    "mixin _HomePageMoreFiltersBodyColor on _HomePageMoreFiltersMileage {\n"
    "  List<Widget> _moreFiltersBodyColorWidgets(\n"
    "    BuildContext context,\n"
    "    void Function(void Function()) setStateDialog,\n"
    "    MoreFiltersDialogStyle style,\n"
    "  ) {\n"
    "    return <Widget>[\n"
    f"{body_widgets}\n"
    "    ];\n"
    "  }\n"
    "}\n",
    encoding="utf-8",
)

MID.write_text(
    "part of 'home_flow.dart';\n\n"
    "mixin _HomePageMoreFiltersMid on _HomePageMoreFiltersBodyColor {\n"
    "  List<Widget> _moreFiltersMidWidgets(\n"
    "    BuildContext context,\n"
    "    void Function(void Function()) setStateDialog,\n"
    "    MoreFiltersDialogStyle style,\n"
    "  ) => [\n"
    "        ..._moreFiltersMileageWidgets(context, setStateDialog, style),\n"
    "        ..._moreFiltersBodyColorWidgets(context, setStateDialog, style),\n"
    "      ];\n"
    "}\n",
    encoding="utf-8",
)

flow_text = FLOW.read_text(encoding="utf-8")
for part in ("home_more_filters_mileage.dart", "home_more_filters_body_color.dart"):
    if part not in flow_text:
        flow_text = flow_text.replace(
            "part 'home_more_filters_mid.dart';",
            f"part '{part}';\npart 'home_more_filters_mid.dart';",
        )
FLOW.write_text(flow_text, encoding="utf-8")

page = REPO / "lib/features/home/home_page.dart"
page.write_text(
    page.read_text(encoding="utf-8").replace(
        "_HomePageMoreFiltersYear,\n        _HomePageMoreFiltersMid,",
        "_HomePageMoreFiltersYear,\n        _HomePageMoreFiltersMileage,\n        _HomePageMoreFiltersBodyColor,\n        _HomePageMoreFiltersMid,",
    ),
    encoding="utf-8",
)

print("split at", split_line, "mileage", split_line - 9, "body", len(lines) - split_line - 2)
