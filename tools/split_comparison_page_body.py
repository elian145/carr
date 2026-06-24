"""Split comparison_page_body.dart into empty-state and filled-state parts."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PAGE = REPO / "lib/pages/comparison_page.dart"
BODY = REPO / "lib/pages/comparison_page_body.dart"
OUT = REPO / "lib/pages"

THEME_PREAMBLE = """    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final lightInk = AppThemes.darkHomeShellBackground;
    final lightInkMuted = lightInk.withValues(alpha: 0.72);
"""

body_lines = BODY.read_text(encoding="utf-8").splitlines()
empty_if = next(i for i, line in enumerate(body_lines) if line.strip() == "if (cars.isEmpty) {")
empty_return = next(
    i for i in range(empty_if, len(body_lines)) if body_lines[i].strip().startswith("return Center(")
)
empty_end = next(
    i
    for i in range(empty_return, len(body_lines))
    if body_lines[i].strip() == ");"
    and i + 1 < len(body_lines)
    and body_lines[i + 1].strip() == "}"
)
filled_return = next(
    i for i, line in enumerate(body_lines) if line.strip().startswith("return ListView(")
)
filled_end = next(
    i
    for i in range(len(body_lines) - 1, filled_return, -1)
    if body_lines[i].strip() == ");"
)

empty_block = "\n".join(body_lines[empty_return : empty_end + 1]).rstrip()
filled_block = "\n".join(body_lines[filled_return : filled_end + 1]).rstrip()

(BODY).write_text(
    "part of 'comparison_page.dart';\n\n"
    "extension _CarComparisonPageBody on CarComparisonPage {\n"
    "  Widget _buildComparisonBody(\n"
    "    BuildContext context,\n"
    "    CarComparisonStore comparisonStore,\n"
    "  ) {\n"
    "    final cars = comparisonStore.comparisonCars;\n"
    "    if (cars.isEmpty) {\n"
    "      return _buildComparisonEmptyState(context);\n"
    "    }\n"
    "    return _buildComparisonFilledState(context, comparisonStore, cars);\n"
    "  }\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "comparison_page_body_empty.dart").write_text(
    "part of 'comparison_page.dart';\n\n"
    "extension _CarComparisonPageBodyEmpty on CarComparisonPage {\n"
    "  Widget _buildComparisonEmptyState(BuildContext context) {\n"
    + THEME_PREAMBLE
    + "\n"
    + empty_block
    + "\n  }\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "comparison_page_body_filled.dart").write_text(
    "part of 'comparison_page.dart';\n\n"
    "extension _CarComparisonPageBodyFilled on CarComparisonPage {\n"
    "  Widget _buildComparisonFilledState(\n"
    "    BuildContext context,\n"
    "    CarComparisonStore comparisonStore,\n"
    "    List<Map<String, dynamic>> cars,\n"
    "  ) {\n"
    + THEME_PREAMBLE
    + "\n"
    + filled_block
    + "\n  }\n"
    "}\n",
    encoding="utf-8",
)

page_lines = PAGE.read_text(encoding="utf-8").splitlines()
if not any("comparison_page_body_empty.dart" in line for line in page_lines):
    page_out = []
    for line in page_lines:
        if line.strip() == "part 'comparison_page_body.dart';":
            page_out.append("part 'comparison_page_body_empty.dart';")
            page_out.append("part 'comparison_page_body_filled.dart';")
        page_out.append(line)
    PAGE.write_text("\n".join(page_out) + "\n", encoding="utf-8")

print("Split comparison_page_body")
