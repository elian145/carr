"""Split car_details_page.dart into fields + mixin parts."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/pages/car_details_page.dart"
OUT = REPO / "lib/features/listing"

lines = FILE.read_text(encoding="utf-8").splitlines()

widget_start = next(i for i, line in enumerate(lines) if line.startswith("class CarDetailsPage"))
state_start = next(i for i, line in enumerate(lines) if line.startswith("class _CarDetailsPageState"))
titles_start = next(i for i, line in enumerate(lines) if line.strip().startswith("void _onListingLayoutChanged"))
owner_start = next(i for i, line in enumerate(lines) if line.strip().startswith("Future<void> _loadFavoriteStatus"))
media_start = next(i for i, line in enumerate(lines) if line.strip().startswith("List<String> get _imageUrls"))
lifecycle_start = next(i for i, line in enumerate(lines) if line.strip().startswith("void _onScroll()"))
load_start = next(i for i, line in enumerate(lines) if line.strip().startswith("Future<void> _loadCar()"))
contact_start = next(i for i, line in enumerate(lines) if line.strip().startswith("Widget _buildContactButtonsRow()"))
similar_start = next(i for i, line in enumerate(lines) if line.strip().startswith("Future<void> _loadSimilarAndRelated()"))
build_start = next(
    i
    for i, line in enumerate(lines)
    if "Widget build(BuildContext context)" in line
)
if build_start > 0 and lines[build_start - 1].strip() == "@override":
    build_start -= 1

imports = "\n".join(lines[:widget_start]).rstrip()
widget_block = "\n".join(lines[widget_start:state_start]).rstrip()
fields_block = "\n".join(lines[state_start + 1 : titles_start]).rstrip()
titles_block = "\n".join(lines[titles_start:owner_start]).rstrip()
owner_block = "\n".join(lines[owner_start:media_start]).rstrip()
media_block = "\n".join(lines[media_start:lifecycle_start]).rstrip()
lifecycle_block = "\n".join(lines[lifecycle_start:load_start]).rstrip()
load_block = "\n".join(lines[load_start:contact_start] + [""] + lines[similar_start:build_start]).rstrip()
contact_block = "\n".join(lines[contact_start:similar_start]).rstrip()
build_block = "\n".join(lines[build_start:-1]).rstrip()

init_block = ""
lifecycle_body = lifecycle_block
for marker in ("@override\n  void initState()", "void initState()"):
    if marker.replace("\n", "\n") in lifecycle_block:
        pass
init_start_in_lifecycle = None
for i, line in enumerate(lines[lifecycle_start:load_start]):
    if line.strip() == "void initState() {" or (
        i > 0
        and lines[lifecycle_start + i - 1].strip() == "@override"
        and line.strip() == "void initState() {"
    ):
        init_start_in_lifecycle = lifecycle_start + i - (
            1 if lines[lifecycle_start + i - 1].strip() == "@override" else 0
        )
        break

dispose_end = load_start
for i in range(lifecycle_start, load_start):
    if lines[i].strip() == "void dispose() {":
        depth = 0
        for j in range(i, load_start):
            depth += lines[j].count("{") - lines[j].count("}")
            if depth == 0 and j > i:
                dispose_end = j + 1
                break
        break

if init_start_in_lifecycle is not None:
    init_block = "\n".join(lines[init_start_in_lifecycle:dispose_end]).rstrip()
    lifecycle_body = "\n".join(
        lines[lifecycle_start:init_start_in_lifecycle] + lines[dispose_end:load_start]
    ).rstrip()

parts = [
    "car_details_page_fields.dart",
    "car_details_page_titles.dart",
    "car_details_page_owner.dart",
    "car_details_page_media.dart",
    "car_details_page_lifecycle.dart",
    "car_details_page_load.dart",
    "car_details_page_init.dart",
    "car_details_page_contact.dart",
    "car_details_page_build.dart",
]

part_lines = "\n".join(f"part '../../pages/{p}';" if False else f"part '../pages/{p}';" for p in parts)
# Parts live next to page file in lib/pages/
part_lines = "\n".join(f"part '{p}';" for p in parts)

(FILE).write_text(
    imports
    + "\n\n"
    + part_lines
    + "\n\n"
    + widget_block
    + "\n\n"
    + "class _CarDetailsPageState extends _CarDetailsPageFields\n"
    + "    with\n"
    + "        _CarDetailsPageTitles,\n"
    + "        _CarDetailsPageOwner,\n"
    + "        _CarDetailsPageMedia,\n"
    + "        _CarDetailsPageLifecycle,\n"
    + "        _CarDetailsPageLoad,\n"
    + "        _CarDetailsPageInit,\n"
    + "        _CarDetailsPageContact,\n"
    + "        _CarDetailsPageBuild {}\n",
    encoding="utf-8",
)

OUT = REPO / "lib/pages"

(OUT / "car_details_page_fields.dart").write_text(
    "part of 'car_details_page.dart';\n\n"
    "abstract class _CarDetailsPageFields extends State<CarDetailsPage> {\n"
    f"{fields_block}\n"
    "}\n",
    encoding="utf-8",
)

mixins = [
    ("car_details_page_titles.dart", "_CarDetailsPageTitles", "_CarDetailsPageFields", titles_block),
    ("car_details_page_owner.dart", "_CarDetailsPageOwner", "_CarDetailsPageTitles", owner_block),
    ("car_details_page_media.dart", "_CarDetailsPageMedia", "_CarDetailsPageOwner", media_block),
    (
        "car_details_page_lifecycle.dart",
        "_CarDetailsPageLifecycle",
        "_CarDetailsPageMedia",
        lifecycle_body,
    ),
    ("car_details_page_load.dart", "_CarDetailsPageLoad", "_CarDetailsPageLifecycle", load_block),
    ("car_details_page_init.dart", "_CarDetailsPageInit", "_CarDetailsPageLoad", init_block),
    (
        "car_details_page_contact.dart",
        "_CarDetailsPageContact",
        "_CarDetailsPageInit",
        contact_block,
    ),
    ("car_details_page_build.dart", "_CarDetailsPageBuild", "_CarDetailsPageContact", build_block),
]

for filename, mixin_name, on_name, body in mixins:
    (OUT / filename).write_text(
        f"part of 'car_details_page.dart';\n\n"
        f"mixin {mixin_name} on {on_name} {{\n"
        f"{body}\n"
        "}\n",
        encoding="utf-8",
    )

print(
    "Split car_details_page:",
    "fields",
    len(fields_block.splitlines()),
    "build",
    len(build_block.splitlines()),
)
