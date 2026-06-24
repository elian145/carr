"""Split dealer_profile_page.dart into core state and helper extension."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/pages/dealer_profile_page.dart"
OUT = REPO / "lib/pages"

lines = FILE.read_text(encoding="utf-8").splitlines()

class_start = next(i for i, line in enumerate(lines) if line.startswith("class DealerProfilePage"))
state_start = next(i for i, line in enumerate(lines) if line.startswith("class _DealerProfilePageState"))
helpers_start = next(i for i, line in enumerate(lines) if line.strip().startswith("String _tr("))
load_start = next(i for i, line in enumerate(lines) if line.strip().startswith("Future<void> _load()"))
build_start = next(i for i, line in enumerate(lines) if "Widget build(BuildContext context)" in line)
if build_start > 0 and lines[build_start - 1].strip() == "@override":
    build_start -= 1

# End of _load() block.
load_end = load_start
depth = 0
for j in range(load_start, build_start):
    depth += lines[j].count("{") - lines[j].count("}")
    if depth == 0 and j > load_start:
        load_end = j + 1
        break

imports = "\n".join(lines[:class_start]).rstrip()
widget_block = "\n".join(lines[class_start:state_start]).rstrip()
fields_block = "\n".join(lines[state_start + 1 : helpers_start]).rstrip()
load_block = "\n".join(lines[load_start:load_end]).rstrip()
helpers_block = "\n".join(lines[helpers_start:load_start] + [""] + lines[load_end:build_start]).rstrip()

enum_line = next(i for i, line in enumerate(lines) if line.startswith("enum _DealerSection"))
build_block = "\n".join(lines[build_start:enum_line]).rstrip()
if build_block.endswith("\n}"):
    build_block = build_block[:-2].rstrip()
enum_block = "\n".join(lines[enum_line:]).rstrip()

(FILE).write_text(
    imports
    + "\n\n"
    + "part 'dealer_profile_page_helpers.dart';\n\n"
    + widget_block
    + "\n\n"
    + "class _DealerProfilePageState extends State<DealerProfilePage> {\n"
    + fields_block
    + "\n\n"
    + load_block
    + "\n\n"
    + build_block
    + "\n}\n\n"
    + enum_block
    + "\n",
    encoding="utf-8",
)

(OUT / "dealer_profile_page_helpers.dart").write_text(
    "part of 'dealer_profile_page.dart';\n\n"
    "extension _DealerProfilePageHelpers on _DealerProfilePageState {\n"
    f"{helpers_block}\n"
    "}\n",
    encoding="utf-8",
)

print("Split dealer_profile_page:", len(helpers_block.splitlines()))
