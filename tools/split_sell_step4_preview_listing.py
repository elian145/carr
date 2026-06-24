"""Split sell_step4_preview_listing.dart: state fields + helpers extension."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/features/sell/sell_step4_preview_listing.dart"
FLOW = REPO / "lib/features/sell/sell_flow.dart"
OUT = REPO / "lib/features/sell"

lines = FILE.read_text(encoding="utf-8").splitlines()

media_entry_start = next(i for i, line in enumerate(lines) if line.startswith("class _PreviewMediaEntry"))
widget_start = next(i for i, line in enumerate(lines) if line.startswith("class ListingPreviewWidget"))
state_start = next(i for i, line in enumerate(lines) if line.startswith("class _ListingPreviewWidgetState"))
helpers_start = next(i for i, line in enumerate(lines) if line.strip().startswith("void _openCarouselDetail"))
build_start = next(i for i, line in enumerate(lines) if "Widget build(BuildContext context)" in line)
if build_start > 0 and lines[build_start - 1].strip() == "@override":
    build_start -= 1

# Fields + dispose live on the state class (extensions cannot hold fields or override).
fields_end = helpers_start
for i in range(state_start, helpers_start):
    if lines[i].strip().startswith("void dispose()"):
        depth = 0
        for j in range(i, helpers_start):
            depth += lines[j].count("{") - lines[j].count("}")
            if depth == 0 and j > i:
                fields_end = j + 1
                break
        break

header = "\n".join(lines[:media_entry_start]).rstrip()
media_entry = "\n".join(lines[media_entry_start:widget_start]).rstrip()
widget_block = "\n".join(lines[widget_start:state_start]).rstrip()
state_fields = "\n".join(lines[state_start + 1 : fields_end]).rstrip()
helpers_block = "\n".join(lines[fields_end:build_start]).rstrip()
build_block = "\n".join(lines[build_start:-1]).rstrip()

(FILE).write_text(
    header
    + "\n\n"
    + f"{media_entry}\n\n"
    + f"{widget_block}\n\n"
    + "class _ListingPreviewWidgetState extends State<ListingPreviewWidget> {\n"
    + state_fields
    + "\n\n"
    + build_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "sell_step4_preview_helpers.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    "extension _ListingPreviewWidgetHelpers on _ListingPreviewWidgetState {\n"
    f"{helpers_block}\n"
    "}\n",
    encoding="utf-8",
)

flow = FLOW.read_text(encoding="utf-8")
part = "part 'sell_step4_preview_helpers.dart';\n"
if part not in flow:
    flow = flow.replace(
        "part 'sell_step4_preview_listing.dart';\n",
        part + "part 'sell_step4_preview_listing.dart';\n",
    )
FLOW.write_text(flow, encoding="utf-8")

print("Split sell_step4_preview_listing: helpers", len(helpers_block.splitlines()))
