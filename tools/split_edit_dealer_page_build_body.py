"""Split edit_dealer_page_build_body.dart into upper and lower form card mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PAGE = REPO / "lib/pages/edit_dealer_page.dart"
BODY = REPO / "lib/pages/edit_dealer_page_build_body.dart"
OUT = REPO / "lib/pages"

PREAMBLE = """    final logoUrl = buildMediaUrl((_currentLogo ?? '').trim());
    final coverUrl = buildMediaUrl((_currentCover ?? '').trim());
    final brightness = Theme.of(context).brightness;
    final cardShape = _pageCardShape(brightness);
    final isLightShell = brightness == Brightness.light;
    final dividerColor = isLightShell ? Colors.grey.shade200 : Colors.white12;
    final cardFill = isLightShell
        ? Colors.white
        : Color.alphaBlend(
            Colors.white.withValues(alpha: 0.06),
            AppThemes.darkHomeShellBackground,
          );
"""

PREAMBLE_UPPER = PREAMBLE

PREAMBLE_LOWER = """    final brightness = Theme.of(context).brightness;
    final cardShape = _pageCardShape(brightness);
    final isLightShell = brightness == Brightness.light;
    final dividerColor = isLightShell ? Colors.grey.shade200 : Colors.white12;
    final cardFill = isLightShell
        ? Colors.white
        : Color.alphaBlend(
            Colors.white.withValues(alpha: 0.06),
            AppThemes.darkHomeShellBackground,
          );
"""

lines = BODY.read_text(encoding="utf-8").splitlines()
upper_start = next(
    i for i, line in enumerate(lines) if line.strip() == "Card(" and lines[i + 1].strip() == "color: cardFill,"
)
opening_hours = next(i for i, line in enumerate(lines) if "Opening hours" in line)
lower_start = next(
    i for i in range(opening_hours, 0, -1) if lines[i].strip() == "const SizedBox(height: 12),"
)
upper_block = "\n".join(lines[upper_start:lower_start]).rstrip()
list_children_close = next(
    i
    for i in range(len(lines) - 1, lower_start, -1)
    if lines[i].strip() == "],"
    and lines[i].startswith("              ")
)
lower_end = list_children_close - 1
lower_block = "\n".join(lines[lower_start:lower_end + 1]).rstrip()

(BODY).write_text(
    "part of 'edit_dealer_page.dart';\n\n"
    "mixin _EditDealerPageBuildBody on _EditDealerPageBuildBodyLower {\n"
    "  Widget _buildEditDealerBody(BuildContext context) {\n"
    "      return Stack(\n"
    "        children: [\n"
    "          Container(\n"
    "            decoration: AppThemes.shellBackgroundDecoration(\n"
    "              Theme.of(context).brightness,\n"
    "            ),\n"
    "          ),\n"
    "          Form(\n"
    "            key: _formKey,\n"
    "            child: ListView(\n"
    "              padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),\n"
    "              children: [\n"
    "                ..._editDealerUpperFormCards(context),\n"
    "                ..._editDealerLowerFormCards(context),\n"
    "              ],\n"
    "            ),\n"
    "          ),\n"
    "        ],\n"
    "      );\n"
    "  }\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "edit_dealer_page_build_body_upper.dart").write_text(
    "part of 'edit_dealer_page.dart';\n\n"
    "mixin _EditDealerPageBuildBodyUpper on _EditDealerPageSave {\n"
    "  List<Widget> _editDealerUpperFormCards(BuildContext context) {\n"
    + PREAMBLE_UPPER
    + "\n    return [\n"
    + upper_block
    + "\n    ];\n"
    "  }\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "edit_dealer_page_build_body_lower.dart").write_text(
    "part of 'edit_dealer_page.dart';\n\n"
    "mixin _EditDealerPageBuildBodyLower on _EditDealerPageBuildBodyUpper {\n"
    "  List<Widget> _editDealerLowerFormCards(BuildContext context) {\n"
    + PREAMBLE_LOWER
    + "\n    return [\n"
    + lower_block
    + "\n    ];\n"
    "  }\n"
    "}\n",
    encoding="utf-8",
)

page = PAGE.read_text(encoding="utf-8")
if "edit_dealer_page_build_body_upper.dart" not in page:
    page = page.replace(
        "part 'edit_dealer_page_build_body.dart';\n",
        "part 'edit_dealer_page_build_body_upper.dart';\n"
        "part 'edit_dealer_page_build_body_lower.dart';\n"
        "part 'edit_dealer_page_build_body.dart';\n",
    )
if "_EditDealerPageBuildBodyUpper" not in page:
    page = page.replace(
        "        _EditDealerPageBuildBody,\n",
        "        _EditDealerPageBuildBodyUpper,\n"
        "        _EditDealerPageBuildBodyLower,\n"
        "        _EditDealerPageBuildBody,\n",
    )
PAGE.write_text(page, encoding="utf-8")

print("Split edit_dealer_page_build_body")
