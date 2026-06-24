"""Split dealer_location_picker_page.dart into fields, load, and core mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/pages/dealer_location_picker_page.dart"
OUT = REPO / "lib/pages"

lines = FILE.read_text(encoding="utf-8").splitlines()

const_line = next(i for i, line in enumerate(lines) if line.startswith("const LatLng _kDefaultMapCenter"))
widget_start = next(
    i for i, line in enumerate(lines) if line.startswith("///") or line.startswith("class DealerLocationPickerPage")
)
state_start = next(i for i, line in enumerate(lines) if line.startswith("class _DealerLocationPickerPageState"))
init_start = next(
    i
    for i, line in enumerate(lines)
    if line.strip() == "@override" and i + 1 < len(lines) and "void initState()" in lines[i + 1]
)
dispose_start = next(
    i
    for i, line in enumerate(lines)
    if line.strip() == "@override" and i + 1 < len(lines) and "void dispose()" in lines[i + 1]
)
build_start = next(i for i, line in enumerate(lines) if "Widget build(BuildContext context)" in line)
if build_start > 0 and lines[build_start - 1].strip() == "@override":
    build_start -= 1

header = "\n".join(lines[:const_line]).rstrip()
const_block = "\n".join(lines[const_line:widget_start]).rstrip()
widget_block = "\n".join(lines[widget_start:state_start]).rstrip()
fields_block = "\n".join(lines[state_start + 1 : init_start]).rstrip()
super_dispose_line = next(
    i for i in range(dispose_start, len(lines)) if "super.dispose();" in lines[i]
)
dispose_end = next(
    i for i in range(super_dispose_line + 1, len(lines)) if lines[i].strip() == "}"
) + 1
dispose_block = "\n".join(lines[dispose_start:dispose_end]).rstrip()
load_block = "\n".join(lines[init_start:dispose_start] + lines[dispose_end:build_start]).rstrip()
core_block = "\n".join(lines[build_start:-1]).rstrip()

(FILE).write_text(
    header
    + "\n\n"
    + "part 'dealer_location_picker_page_fields.dart';\n"
    + "part 'dealer_location_picker_page_load.dart';\n"
    + "part 'dealer_location_picker_page_core.dart';\n\n"
    + const_block
    + "\n\n"
    + widget_block
    + "\n\n"
    + "class _DealerLocationPickerPageState extends _DealerLocationPickerPageFields\n"
    + "    with _DealerLocationPickerPageLoad, _DealerLocationPickerPageCore {}\n",
    encoding="utf-8",
)

(OUT / "dealer_location_picker_page_fields.dart").write_text(
    "part of 'dealer_location_picker_page.dart';\n\n"
    "abstract class _DealerLocationPickerPageFields extends State<DealerLocationPickerPage> {\n"
    + fields_block
    + "\n\n"
    + dispose_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "dealer_location_picker_page_load.dart").write_text(
    "part of 'dealer_location_picker_page.dart';\n\n"
    "mixin _DealerLocationPickerPageLoad on _DealerLocationPickerPageFields {\n"
    + load_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "dealer_location_picker_page_core.dart").write_text(
    "part of 'dealer_location_picker_page.dart';\n\n"
    "mixin _DealerLocationPickerPageCore on _DealerLocationPickerPageLoad {\n"
    + core_block
    + "\n}\n",
    encoding="utf-8",
)

print("Split dealer_location_picker_page")
