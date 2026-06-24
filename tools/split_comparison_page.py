"""Split comparison_page.dart: build shell + helper extension part."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/pages/comparison_page.dart"
OUT = REPO / "lib/pages"

lines = FILE.read_text(encoding="utf-8").splitlines()

class_start = next(i for i, line in enumerate(lines) if line.startswith("class CarComparisonPage"))
build_start = next(i for i, line in enumerate(lines) if "Widget build(BuildContext context)" in line)
helpers_start = next(i for i, line in enumerate(lines) if line.strip().startswith("Widget _buildCarImage"))

imports = "\n".join(lines[:class_start]).rstrip()
class_header = "\n".join(lines[class_start : build_start + 1]).rstrip()
build_block = "\n".join(lines[build_start + 1 : helpers_start]).rstrip()
helpers_block = "\n".join(lines[helpers_start:-1]).rstrip()

(FILE).write_text(
    imports
    + "\n\n"
    + "part 'comparison_page_helpers.dart';\n\n"
    + class_header
    + "\n"
    + build_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "comparison_page_helpers.dart").write_text(
    "part of 'comparison_page.dart';\n\n"
    "extension _CarComparisonPageHelpers on CarComparisonPage {\n"
    f"{helpers_block}\n"
    "}\n",
    encoding="utf-8",
)

print("Split comparison_page: build", len(build_block.splitlines()), "helpers", len(helpers_block.splitlines()))
