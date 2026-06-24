"""Split edit_dealer_page_build.dart into shell and body mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/pages/edit_dealer_page_build.dart"
PAGE = REPO / "lib/pages/edit_dealer_page.dart"
OUT = REPO / "lib/pages"

lines = FILE.read_text(encoding="utf-8").splitlines()

build_start = next(i for i, line in enumerate(lines) if "Widget build(BuildContext context)" in line)
if build_start > 0 and lines[build_start - 1].strip() == "@override":
    build_start -= 1

locals_start = next(i for i, line in enumerate(lines) if line.strip().startswith("final logoUrl"))
hydrating_line = next(i for i, line in enumerate(lines) if "if (_hydratingProfile)" in line)
body_locals_block = "\n".join(lines[locals_start:hydrating_line]).rstrip()

shell_locals_lines = [
    "    final brightness = Theme.of(context).brightness;",
    "    final isLightShell = brightness == Brightness.light;",
    "    final barSurface = Color.alphaBlend(",
    "      Theme.of(context).colorScheme.surface.withValues(alpha: 0.88),",
    "      isLightShell ? Colors.white : AppThemes.darkHomeShellBackground,",
    "    );",
]

body_line = next(i for i, line in enumerate(lines) if line.strip().startswith("body: Stack("))
column_close = next(
    i
    for i in range(body_line + 1, len(lines))
    if lines[i].rstrip() == "      )," and lines[i + 1].strip() == ");"
)
column_start = body_line + 1

body_block = "\n".join(
    [body_locals_block, "", "      return Stack("]
    + lines[column_start:column_close]
    + ["      );"]
).rstrip()

shell_block = "\n".join(
    lines[build_start:locals_start]
    + shell_locals_lines
    + [""]
    + lines[hydrating_line:body_line]
    + ["      body: _buildEditDealerBody(context),", "    );", "  }"]
).rstrip()

(OUT / "edit_dealer_page_build_body.dart").write_text(
    "part of 'edit_dealer_page.dart';\n\n"
    "mixin _EditDealerPageBuildBody on _EditDealerPageSave {\n"
    "  Widget _buildEditDealerBody(BuildContext context) {\n"
    f"{body_block}\n"
    "  }\n"
    "}\n",
    encoding="utf-8",
)

(FILE).write_text(
    "part of 'edit_dealer_page.dart';\n\n"
    "mixin _EditDealerPageBuild on _EditDealerPageBuildBody {\n"
    f"{shell_block}\n"
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
    PAGE.write_text(page, encoding="utf-8")

if "_EditDealerPageBuildBodyUpper" not in page:
    page = PAGE.read_text(encoding="utf-8")
    page = page.replace(
        "        _EditDealerPageBuildBody,\n",
        "        _EditDealerPageBuildBodyUpper,\n"
        "        _EditDealerPageBuildBodyLower,\n"
        "        _EditDealerPageBuildBody,\n",
    )
    PAGE.write_text(page, encoding="utf-8")

if "_EditDealerPageBuildBody" not in page:
    page = PAGE.read_text(encoding="utf-8")
    page = page.replace(
        "        _EditDealerPageBuild {}",
        "        _EditDealerPageBuildBody,\n        _EditDealerPageBuild {}",
    )
    PAGE.write_text(page, encoding="utf-8")

# Drop barSurface from body locals (only used in shell).
body_path = OUT / "edit_dealer_page_build_body.dart"
body_text = body_path.read_text(encoding="utf-8")
bar_start = body_text.find("    final barSurface = Color.alphaBlend(")
if bar_start != -1:
    bar_end = body_text.find("    );\n", bar_start) + len("    );\n")
    body_path.write_text(body_text[:bar_start] + body_text[bar_end:], encoding="utf-8")

print("Split edit_dealer_page_build")
