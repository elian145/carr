"""Split analytics_page into fields, load, widgets, listing, and core mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PAGE = REPO / "lib/pages/analytics_page.dart"
WIDGETS = REPO / "lib/pages/analytics_page_widgets.dart"
OUT = REPO / "lib/pages"

page_lines = PAGE.read_text(encoding="utf-8").splitlines()
widget_lines = WIDGETS.read_text(encoding="utf-8").splitlines()

widget_start = next(i for i, line in enumerate(page_lines) if line.startswith("class AnalyticsPage"))
state_start = next(i for i, line in enumerate(page_lines) if line.startswith("class _AnalyticsPageState"))
helpers_start = next(i for i, line in enumerate(page_lines) if line.strip().startswith("String getApiBase()"))
build_start = next(i for i, line in enumerate(page_lines) if "Widget build(BuildContext context)" in line)
if build_start > 0 and page_lines[build_start - 1].strip() == "@override":
    build_start -= 1

part_line = next(i for i, line in enumerate(page_lines) if line.startswith("part "))
header = "\n".join(page_lines[:part_line]).rstrip()
widget_block = "\n".join(page_lines[widget_start:state_start]).rstrip()
fields_block = "\n".join(page_lines[state_start + 1 : helpers_start]).rstrip()
load_block = "\n".join(page_lines[helpers_start:build_start]).rstrip()
core_block = "\n".join(page_lines[build_start:-1]).rstrip()

widgets_block = "\n".join(widget_lines[3:-1]).rstrip()

(PAGE).write_text(
    header
    + "\npart 'analytics_page_fields.dart';\n"
    + "part 'analytics_page_load.dart';\n"
    + "part 'analytics_page_listing_selection.dart';\n"
    + "part 'analytics_page_listing_card.dart';\n"
    + "part 'analytics_page_widgets.dart';\n"
    + "part 'analytics_page_core.dart';\n\n"
    + widget_block
    + "\n\n"
    + "class _AnalyticsPageState extends _AnalyticsPageFields\n"
    + "    with\n"
    + "        _AnalyticsPageLoad,\n"
    + "        _AnalyticsPageListingCard,\n"
    + "        _AnalyticsPageListingSelection,\n"
    + "        _AnalyticsPageWidgets,\n"
    + "        _AnalyticsPageCore {}\n",
    encoding="utf-8",
)

(OUT / "analytics_page_fields.dart").write_text(
    "part of 'analytics_page.dart';\n\n"
    "abstract class _AnalyticsPageFields extends State<AnalyticsPage> {\n"
    + fields_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "analytics_page_load.dart").write_text(
    "part of 'analytics_page.dart';\n\n"
    "mixin _AnalyticsPageLoad on _AnalyticsPageFields {\n"
    + load_block
    + "\n}\n",
    encoding="utf-8",
)

(WIDGETS).write_text(
    "part of 'analytics_page.dart';\n\n"
    "mixin _AnalyticsPageWidgets on _AnalyticsPageListingSelection {\n"
    + widgets_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "analytics_page_core.dart").write_text(
    "part of 'analytics_page.dart';\n\n"
    "mixin _AnalyticsPageCore on _AnalyticsPageWidgets {\n"
    + core_block
    + "\n}\n",
    encoding="utf-8",
)

print("Split analytics_page_widgets (listing: run split_analytics_page_listing_widgets.py)")
