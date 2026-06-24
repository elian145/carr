"""Split home_slivers.dart into filter card and feed sliver mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SLIVERS = REPO / "lib/features/home/home_slivers.dart"
FLOW = REPO / "lib/features/home/home_flow.dart"
PAGE = REPO / "lib/features/home/home_page.dart"
OUT = REPO / "lib/features/home"

lines = SLIVERS.read_text(encoding="utf-8").splitlines()
feed_line = next(
    i for i, line in enumerate(lines) if "List<Widget> _buildHomeFeedSlivers" in line
)

filter_block = "\n".join(lines[3:feed_line]).rstrip()
feed_block = "\n".join(lines[feed_line:-1]).rstrip()

(OUT / "home_slivers_filter_card.dart").write_text(
    "part of 'home_flow.dart';\n\n"
    "mixin _HomePageSliversFilterCard on _HomePageMoreFiltersDialog {\n"
    f"{filter_block}\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "home_slivers.dart").write_text(
    "part of 'home_flow.dart';\n\n"
    "mixin _HomePageSlivers on _HomePageSliversFilterCard {\n"
    f"{feed_block}\n"
    "}\n",
    encoding="utf-8",
)

flow = FLOW.read_text(encoding="utf-8")
if "home_slivers_filter_card.dart" not in flow:
    flow = flow.replace(
        "part 'home_slivers.dart';",
        "part 'home_slivers_filter_card.dart';\npart 'home_slivers.dart';",
    )
    FLOW.write_text(flow, encoding="utf-8")

page = PAGE.read_text(encoding="utf-8")
page = page.replace(
    "_HomePageMoreFiltersDialog,\n        _HomePageSlivers,",
    "_HomePageMoreFiltersDialog,\n        _HomePageSliversFilterCard,\n        _HomePageSlivers,",
)
PAGE.write_text(page, encoding="utf-8")
print("filter", len(filter_block.splitlines()), "feed", len(feed_block.splitlines()))
