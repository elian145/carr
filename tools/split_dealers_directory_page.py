"""Split dealers_directory_page.dart into fields, load, widgets, and core mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/pages/dealers_directory_page.dart"
OUT = REPO / "lib/pages"

lines = FILE.read_text(encoding="utf-8").splitlines()

widget_start = next(
    i for i, line in enumerate(lines) if line.startswith("///") or line.startswith("class DealersDirectoryPage")
)
state_start = next(i for i, line in enumerate(lines) if line.startswith("class _DealersDirectoryPageState"))
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
dispose_end = next(i for i in range(dispose_start, len(lines)) if "super.dispose();" in lines[i]) + 1
widgets_start = next(i for i, line in enumerate(lines) if line.strip().startswith("Widget _buildSearchBar"))
build_start = next(i for i, line in enumerate(lines) if "Widget build(BuildContext context)" in line)
if build_start > 0 and lines[build_start - 1].strip() == "@override":
    build_start -= 1

header = "\n".join(lines[:widget_start]).rstrip()
widget_block = "\n".join(lines[widget_start:state_start]).rstrip()
fields_block = "\n".join(lines[state_start + 1 : init_start] + lines[dispose_start : dispose_end + 1]).rstrip()
load_block = "\n".join(lines[init_start:dispose_start] + lines[dispose_end + 1 : widgets_start]).rstrip()
widgets_block = "\n".join(lines[widgets_start:build_start]).rstrip()
core_block = "\n".join(lines[build_start:-1]).rstrip()

(FILE).write_text(
    header
    + "\n\n"
    + "part 'dealers_directory_page_fields.dart';\n"
    + "part 'dealers_directory_page_load.dart';\n"
    + "part 'dealers_directory_page_widgets.dart';\n"
    + "part 'dealers_directory_page_core.dart';\n\n"
    + widget_block
    + "\n\n"
    + "class _DealersDirectoryPageState extends _DealersDirectoryPageFields\n"
    + "    with\n"
    + "        _DealersDirectoryPageLoad,\n"
    + "        _DealersDirectoryPageWidgets,\n"
    + "        _DealersDirectoryPageCore {}\n",
    encoding="utf-8",
)

(OUT / "dealers_directory_page_fields.dart").write_text(
    "part of 'dealers_directory_page.dart';\n\n"
    "abstract class _DealersDirectoryPageFields extends State<DealersDirectoryPage> {\n"
    + fields_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "dealers_directory_page_load.dart").write_text(
    "part of 'dealers_directory_page.dart';\n\n"
    "mixin _DealersDirectoryPageLoad on _DealersDirectoryPageFields {\n"
    + load_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "dealers_directory_page_widgets.dart").write_text(
    "part of 'dealers_directory_page.dart';\n\n"
    "mixin _DealersDirectoryPageWidgets on _DealersDirectoryPageLoad {\n"
    + widgets_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "dealers_directory_page_core.dart").write_text(
    "part of 'dealers_directory_page.dart';\n\n"
    "mixin _DealersDirectoryPageCore on _DealersDirectoryPageWidgets {\n"
    + core_block
    + "\n}\n",
    encoding="utf-8",
)

print("Split dealers_directory_page")

static_fields = ("_brandOrange", "_perPage")
for path in (
    OUT / "dealers_directory_page_load.dart",
    OUT / "dealers_directory_page_widgets.dart",
    OUT / "dealers_directory_page_core.dart",
):
    text = path.read_text(encoding="utf-8")
    for name in static_fields:
        text = text.replace(name, f"_DealersDirectoryPageFields.{name}")
    path.write_text(text, encoding="utf-8")
