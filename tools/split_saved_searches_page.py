"""Split saved_searches_page into fields, load, and helper mixins."""
from __future__ import annotations

import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PAGE = REPO / "lib/pages/saved_searches_page.dart"
HELPERS = REPO / "lib/pages/saved_searches_page_helpers.dart"
OUT = REPO / "lib/pages"

page_lines = PAGE.read_text(encoding="utf-8").splitlines()
helper_lines = HELPERS.read_text(encoding="utf-8").splitlines()

part_line = next(i for i, line in enumerate(page_lines) if line.startswith("part "))
header = "\n".join(page_lines[:part_line]).rstrip()

widget_start = next(i for i, line in enumerate(page_lines) if line.startswith("class SavedSearchesPage"))
state_start = next(i for i, line in enumerate(page_lines) if line.startswith("class _SavedSearchesPageState"))
init_start = next(
    i
    for i, line in enumerate(page_lines)
    if line.strip() == "@override" and i + 1 < len(page_lines) and "void initState()" in page_lines[i + 1]
)
build_start = next(i for i, line in enumerate(page_lines) if "Widget build(BuildContext context)" in line)
if build_start > 0 and page_lines[build_start - 1].strip() == "@override":
    build_start -= 1

widget_block = "\n".join(page_lines[widget_start:state_start]).rstrip()
fields_block = "\n".join(page_lines[state_start + 1 : init_start]).rstrip()
load_block = "\n".join(page_lines[init_start:build_start]).rstrip()
core_block = "\n".join(page_lines[build_start:-1]).rstrip()

actions_start = next(i for i, line in enumerate(helper_lines) if line.strip().startswith("void _applySearch"))
details_start = next(
    i for i, line in enumerate(helper_lines) if line.strip().startswith("Widget _buildDetailedFilterList")
)
capitalize_start = next(
    i for i, line in enumerate(helper_lines) if line.strip().startswith("String _capitalizeFirst")
)

helpers_block = "\n".join(helper_lines[3:actions_start] + helper_lines[capitalize_start:-1]).rstrip()
actions_block = "\n".join(helper_lines[actions_start:details_start]).rstrip()
details_block = "\n".join(helper_lines[details_start:capitalize_start]).rstrip()

(PAGE).write_text(
    header
    + "\npart 'saved_searches_page_fields.dart';\n"
    + "part 'saved_searches_page_helpers.dart';\n"
    + "part 'saved_searches_page_actions.dart';\n"
    + "part 'saved_searches_page_filter_details.dart';\n"
    + "part 'saved_searches_page_core.dart';\n\n"
    + widget_block
    + "\n\n"
    + "class _SavedSearchesPageState extends _SavedSearchesPageFields\n"
    + "    with\n"
    + "        _SavedSearchesPageLoad,\n"
    + "        _SavedSearchesPageHelpers,\n"
    + "        _SavedSearchesPageFilterDetails,\n"
    + "        _SavedSearchesPageActions,\n"
    + "        _SavedSearchesPageCore {}\n",
    encoding="utf-8",
)

(OUT / "saved_searches_page_fields.dart").write_text(
    "part of 'saved_searches_page.dart';\n\n"
    "abstract class _SavedSearchesPageFields extends State<SavedSearchesPage> {\n"
    + fields_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "saved_searches_page_load.dart").write_text(
    "part of 'saved_searches_page.dart';\n\n"
    "mixin _SavedSearchesPageLoad on _SavedSearchesPageFields {\n"
    + load_block
    + "\n}\n",
    encoding="utf-8",
)

(HELPERS).write_text(
    "part of 'saved_searches_page.dart';\n\n"
    "mixin _SavedSearchesPageHelpers on _SavedSearchesPageLoad {\n"
    + helpers_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "saved_searches_page_actions.dart").write_text(
    "part of 'saved_searches_page.dart';\n\n"
    "mixin _SavedSearchesPageActions on _SavedSearchesPageFilterDetails {\n"
    + actions_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "saved_searches_page_filter_details.dart").write_text(
    "part of 'saved_searches_page.dart';\n\n"
    "mixin _SavedSearchesPageFilterDetails on _SavedSearchesPageHelpers {\n"
    + details_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "saved_searches_page_core.dart").write_text(
    "part of 'saved_searches_page.dart';\n\n"
    "mixin _SavedSearchesPageCore on _SavedSearchesPageActions {\n"
    + core_block
    + "\n}\n",
    encoding="utf-8",
)

page_text = PAGE.read_text(encoding="utf-8")
if "saved_searches_page_load.dart" not in page_text:
    page_text = page_text.replace(
        "part 'saved_searches_page_fields.dart';\n",
        "part 'saved_searches_page_fields.dart';\npart 'saved_searches_page_load.dart';\n",
    )
    PAGE.write_text(page_text, encoding="utf-8")

print("Split saved_searches_page")
