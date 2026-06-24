"""Split analytics_page.dart into core state and widget helper extension."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/pages/analytics_page.dart"
OUT = REPO / "lib/pages"

lines = FILE.read_text(encoding="utf-8").splitlines()

class_start = next(i for i, line in enumerate(lines) if line.startswith("class AnalyticsPage"))
state_start = next(i for i, line in enumerate(lines) if line.startswith("class _AnalyticsPageState"))
helpers_start = next(i for i, line in enumerate(lines) if line.strip().startswith("Widget _buildErrorState"))
build_start = next(i for i, line in enumerate(lines) if "Widget build(BuildContext context)" in line)
if build_start > 0 and lines[build_start - 1].strip() == "@override":
    build_start -= 1

imports = "\n".join(lines[:class_start]).rstrip()
widget_block = "\n".join(lines[class_start:state_start]).rstrip()
state_block = "\n".join(lines[state_start + 1 : helpers_start]).rstrip()
helpers_block = "\n".join(lines[helpers_start:-1]).rstrip()

(FILE).write_text(
    imports
    + "\n\n"
    + "part 'analytics_page_widgets.dart';\n\n"
    + widget_block
    + "\n\n"
    + "class _AnalyticsPageState extends State<AnalyticsPage> {\n"
    + state_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "analytics_page_widgets.dart").write_text(
    "part of 'analytics_page.dart';\n\n"
    "extension _AnalyticsPageWidgets on _AnalyticsPageState {\n"
    f"{helpers_block}\n"
    "}\n",
    encoding="utf-8",
)

print("Split analytics_page:", len(state_block.splitlines()), len(helpers_block.splitlines()))
