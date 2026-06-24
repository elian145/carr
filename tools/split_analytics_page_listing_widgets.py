"""Split analytics_page_listing_widgets.dart into selection and card mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PAGE = REPO / "lib/pages/analytics_page.dart"
LISTING = REPO / "lib/pages/analytics_page_listing_widgets.dart"
OUT = REPO / "lib/pages"

lines = LISTING.read_text(encoding="utf-8").splitlines()
card_start = next(
    i for i, line in enumerate(lines) if line.strip().startswith("Widget _buildListingCard")
)
metric_start = next(
    i for i, line in enumerate(lines) if line.strip().startswith("Widget _buildModernMetricItem")
)

selection_block = "\n".join(lines[3:card_start]).rstrip()
card_block = "\n".join(lines[card_start:metric_start]).rstrip()
metric_block = "\n".join(lines[metric_start:-1]).rstrip()

(OUT / "analytics_page_listing_card.dart").write_text(
    "part of 'analytics_page.dart';\n\n"
    "mixin _AnalyticsPageListingCard on _AnalyticsPageLoad {\n"
    + card_block
    + "\n\n"
    + metric_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "analytics_page_listing_selection.dart").write_text(
    "part of 'analytics_page.dart';\n\n"
    "mixin _AnalyticsPageListingSelection on _AnalyticsPageListingCard {\n"
    + selection_block
    + "\n}\n",
    encoding="utf-8",
)

LISTING.unlink(missing_ok=True)

page = PAGE.read_text(encoding="utf-8")
page = page.replace(
    "part 'analytics_page_listing_widgets.dart';\n",
    "part 'analytics_page_listing_selection.dart';\n"
    "part 'analytics_page_listing_card.dart';\n",
)
page = page.replace(
    "        _AnalyticsPageListingWidgets,\n",
    "        _AnalyticsPageListingCard,\n"
    "        _AnalyticsPageListingSelection,\n",
)
PAGE.write_text(page, encoding="utf-8")

widgets = OUT / "analytics_page_widgets.dart"
widgets_text = widgets.read_text(encoding="utf-8")
widgets_text = widgets_text.replace(
    "mixin _AnalyticsPageWidgets on _AnalyticsPageListingWidgets {",
    "mixin _AnalyticsPageWidgets on _AnalyticsPageListingSelection {",
)
widgets.write_text(widgets_text, encoding="utf-8")

print("Split analytics_page_listing_widgets")
