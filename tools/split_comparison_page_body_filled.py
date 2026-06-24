"""Split comparison_page_body_filled.dart into header and table extensions."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PAGE = REPO / "lib/pages/comparison_page.dart"
FILLED = REPO / "lib/pages/comparison_page_body_filled.dart"
OUT = REPO / "lib/pages"

THEME_PREAMBLE_HEADER = """    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final lightInk = AppThemes.darkHomeShellBackground;
    final lightInkMuted = lightInk.withValues(alpha: 0.72);
"""

THEME_PREAMBLE_TABLE = """    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lightInk = AppThemes.darkHomeShellBackground;
"""


def _as_return_widget(block: str) -> str:
    block = block.rstrip()
    if block.endswith("),"):
        return block[:-2] + ");"
    if not block.endswith(";"):
        return block + ";"
    return block


lines = FILLED.read_text(encoding="utf-8").splitlines()
header_start = next(i for i, line in enumerate(lines) if line.strip() == "// Header")
header_block_start = next(
    i for i in range(header_start, len(lines)) if lines[i].strip() == "Container("
)
spacer_line = next(
    i for i, line in enumerate(lines) if line.strip() == "SizedBox(height: 20),"
)
table_start = next(i for i, line in enumerate(lines) if line.strip() == "// Comparison Table")
table_block_start = next(
    i for i in range(table_start, len(lines)) if lines[i].strip().startswith("LayoutBuilder(")
)
list_children_close = next(
    i
    for i in range(len(lines) - 1, table_block_start, -1)
    if lines[i].strip() == "],"
    and lines[i].startswith("                ")
)

header_block = _as_return_widget("\n".join(lines[header_block_start:spacer_line]))
table_block = _as_return_widget("\n".join(lines[table_block_start:list_children_close]))

(FILLED).write_text(
    "part of 'comparison_page.dart';\n\n"
    "extension _CarComparisonPageBodyFilled on CarComparisonPage {\n"
    "  Widget _buildComparisonFilledState(\n"
    "    BuildContext context,\n"
    "    CarComparisonStore comparisonStore,\n"
    "    List<Map<String, dynamic>> cars,\n"
    "  ) {\n"
    "    return ListView(\n"
    "      padding: const EdgeInsets.all(16),\n"
    "      children: [\n"
    "        _buildComparisonFilledHeader(context, comparisonStore, cars),\n"
    "        const SizedBox(height: 20),\n"
    "        _buildComparisonFilledTable(context, comparisonStore, cars),\n"
    "      ],\n"
    "    );\n"
    "  }\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "comparison_page_body_filled_header.dart").write_text(
    "part of 'comparison_page.dart';\n\n"
    "extension _CarComparisonPageBodyFilledHeader on CarComparisonPage {\n"
    "  Widget _buildComparisonFilledHeader(\n"
    "    BuildContext context,\n"
    "    CarComparisonStore comparisonStore,\n"
    "    List<Map<String, dynamic>> cars,\n"
    "  ) {\n"
    + THEME_PREAMBLE_HEADER
    + "\n    return "
    + header_block.lstrip()
    + "\n"
    "  }\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "comparison_page_body_filled_table.dart").write_text(
    "part of 'comparison_page.dart';\n\n"
    "extension _CarComparisonPageBodyFilledTable on CarComparisonPage {\n"
    "  Widget _buildComparisonFilledTable(\n"
    "    BuildContext context,\n"
    "    CarComparisonStore comparisonStore,\n"
    "    List<Map<String, dynamic>> cars,\n"
    "  ) {\n"
    + THEME_PREAMBLE_TABLE
    + "\n    return "
    + table_block.lstrip()
    + "\n"
    "  }\n"
    "}\n",
    encoding="utf-8",
)

page = PAGE.read_text(encoding="utf-8")
if "comparison_page_body_filled_header.dart" not in page:
    page = page.replace(
        "part 'comparison_page_body_filled.dart';\n",
        "part 'comparison_page_body_filled_header.dart';\n"
        "part 'comparison_page_body_filled_table.dart';\n"
        "part 'comparison_page_body_filled.dart';\n",
    )
    PAGE.write_text(page, encoding="utf-8")

print("Split comparison_page_body_filled")
