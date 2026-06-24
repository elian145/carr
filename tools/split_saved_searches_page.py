"""Split saved_searches_page.dart: core state + helper extension part."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/pages/saved_searches_page.dart"
OUT = REPO / "lib/pages"

lines = FILE.read_text(encoding="utf-8").splitlines()

class_start = next(i for i, line in enumerate(lines) if line.startswith("class SavedSearchesPage"))
state_start = next(i for i, line in enumerate(lines) if line.startswith("class _SavedSearchesPageState"))
helpers_start = next(
    i for i, line in enumerate(lines) if line.strip().startswith("String _localizedSearchTitle(")
)

imports = "\n".join(lines[:class_start]).rstrip()
widget_block = "\n".join(lines[class_start:state_start]).rstrip()
state_block = "\n".join(lines[state_start + 1 : helpers_start]).rstrip()
helpers_block = "\n".join(lines[helpers_start:-1]).rstrip()

(FILE).write_text(
    imports
    + "\n\n"
    + "part 'saved_searches_page_helpers.dart';\n\n"
    + widget_block
    + "\n\n"
    + "class _SavedSearchesPageState extends State<SavedSearchesPage> {\n"
    + state_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "saved_searches_page_helpers.dart").write_text(
    "part of 'saved_searches_page.dart';\n\n"
    "extension _SavedSearchesPageHelpers on _SavedSearchesPageState {\n"
    f"{helpers_block}\n"
    "}\n",
    encoding="utf-8",
)

print("Split saved_searches_page:", len(state_block.splitlines()), len(helpers_block.splitlines()))
