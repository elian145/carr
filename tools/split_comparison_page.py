"""Split comparison_page.dart into shell, body, and row helper parts."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PAGE = REPO / "lib/pages/comparison_page.dart"
HELPERS = REPO / "lib/pages/comparison_page_helpers.dart"
OUT = REPO / "lib/pages"


def line_indent(line: str) -> int:
    return len(line) - len(line.lstrip())


page_lines = PAGE.read_text(encoding="utf-8").splitlines()
helper_lines = HELPERS.read_text(encoding="utf-8").splitlines()

part_line = next(i for i, line in enumerate(page_lines) if line.startswith("part "))
header = "\n".join(page_lines[:part_line]).rstrip()

build_start = next(i for i, line in enumerate(page_lines) if "Widget build(BuildContext context)" in line)
if build_start > 0 and page_lines[build_start - 1].strip() == "@override":
    build_start -= 1

stack_line = next(i for i, line in enumerate(page_lines) if line.strip() == "body: Stack(")
consumer_line = next(
    i for i in range(stack_line, len(page_lines)) if "Consumer<CarComparisonStore>" in page_lines[i]
)
builder_line = next(
    i
    for i in range(consumer_line, len(page_lines))
    if "builder: (context, comparisonStore, child)" in page_lines[i]
)
body_start = builder_line + 1
body_end = next(
    i
    for i in range(body_start, len(page_lines))
    if page_lines[i].strip() == ");"
    and i + 1 < len(page_lines)
    and page_lines[i + 1].strip() == "},"
    and line_indent(page_lines[i]) == 14
)

body_block = "\n".join(page_lines[body_start : body_end + 1]).rstrip()

shell_build = (
    "\n".join(page_lines[build_start:body_start]).rstrip()
    + "\n              return _buildComparisonBody(context, comparisonStore);\n"
    + "\n".join(page_lines[body_end + 1 : -1]).rstrip()
    + "\n"
)

rows_start = next(
    i for i, line in enumerate(helper_lines) if line.strip().startswith("List<Widget> _buildComparisonRows")
)
image_block = "\n".join(helper_lines[3:rows_start]).rstrip()
rows_block = "\n".join(helper_lines[rows_start:-1]).rstrip()

(PAGE).write_text(
    header
    + "\n\n"
    + "part 'comparison_page_helpers.dart';\n"
    + "part 'comparison_page_rows.dart';\n"
    + "part 'comparison_page_body_empty.dart';\n"
    + "part 'comparison_page_body_filled.dart';\n"
    + "part 'comparison_page_body.dart';\n\n"
    + "class CarComparisonPage extends StatelessWidget {\n"
    + "  const CarComparisonPage({super.key});\n\n"
    + shell_build
    + "}\n",
    encoding="utf-8",
)

(HELPERS).write_text(
    "part of 'comparison_page.dart';\n\n"
    "extension _CarComparisonPageHelpers on CarComparisonPage {\n"
    + image_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "comparison_page_body.dart").write_text(
    "part of 'comparison_page.dart';\n\n"
    "extension _CarComparisonPageBody on CarComparisonPage {\n"
    "  Widget _buildComparisonBody(\n"
    "    BuildContext context,\n"
    "    CarComparisonStore comparisonStore,\n"
    "  ) {\n"
    + body_block
    + "\n  }\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "comparison_page_rows.dart").write_text(
    "part of 'comparison_page.dart';\n\n"
    "extension _CarComparisonPageRows on CarComparisonPage {\n"
    + rows_block
    + "\n}\n",
    encoding="utf-8",
)

print("Split comparison_page")
