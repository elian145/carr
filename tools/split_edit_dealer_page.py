"""Split edit_dealer_page.dart into fields and focused state mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/pages/edit_dealer_page.dart"
OUT = REPO / "lib/pages"

lines = FILE.read_text(encoding="utf-8").splitlines()

widget_start = next(i for i, line in enumerate(lines) if line.startswith("class EditDealerPage"))
day_hours_start = next(i for i, line in enumerate(lines) if line.startswith("class _DayHours"))
state_start = next(i for i, line in enumerate(lines) if line.startswith("class _EditDealerPageState"))
style_start = next(i for i, line in enumerate(lines) if line.strip().startswith("String _tr("))
hours_start = next(i for i, line in enumerate(lines) if line.strip().startswith("String _daySummaryText"))
profile_start = next(i for i, line in enumerate(lines) if line.strip().startswith("void initState()"))
if profile_start > 0 and lines[profile_start - 1].strip() == "@override":
    profile_start -= 1
location_start = next(i for i, line in enumerate(lines) if line.strip().startswith("Future<void> _openMapPicker()"))
media_start = next(i for i, line in enumerate(lines) if line.strip().startswith("Future<void> _pickLogo()"))
save_start = next(i for i, line in enumerate(lines) if line.strip().startswith("Future<void> _save()"))
build_start = next(i for i, line in enumerate(lines) if "Widget build(BuildContext context)" in line)
if build_start > 0 and lines[build_start - 1].strip() == "@override":
    build_start -= 1
dispose_end = location_start
for i in range(profile_start, location_start):
    if lines[i].strip() == "void dispose() {":
        depth = 0
        for j in range(i, location_start):
            depth += lines[j].count("{") - lines[j].count("}")
            if depth == 0 and j > i:
                dispose_end = j + 1
                break
        break

imports = "\n".join(lines[:widget_start]).rstrip()
widget_block = "\n".join(lines[widget_start:day_hours_start]).rstrip()
day_hours_block = "\n".join(lines[day_hours_start:state_start]).rstrip()
fields_block = "\n".join(lines[state_start + 1 : style_start]).rstrip()
style_block = "\n".join(lines[style_start:hours_start]).rstrip()
hours_block = "\n".join(lines[hours_start:profile_start]).rstrip()
profile_block = "\n".join(lines[profile_start:dispose_end]).rstrip()
location_block = "\n".join(lines[dispose_end:media_start]).rstrip()
media_block = "\n".join(lines[media_start:save_start]).rstrip()
save_block = "\n".join(lines[save_start:build_start]).rstrip()
build_block = "\n".join(lines[build_start:-1]).rstrip()
# Strip accidental trailing state-class brace if present.
if build_block.endswith("\n}"):
    build_block = build_block[:-2].rstrip()

parts = [
    "edit_dealer_page_fields.dart",
    "edit_dealer_page_style.dart",
    "edit_dealer_page_hours.dart",
    "edit_dealer_page_profile.dart",
    "edit_dealer_page_location.dart",
    "edit_dealer_page_media.dart",
    "edit_dealer_page_save.dart",
    "edit_dealer_page_build.dart",
]

(FILE).write_text(
    imports
    + "\n\n"
    + "\n".join(f"part '{p}';" for p in parts)
    + "\n\n"
    + widget_block
    + "\n\n"
    + "class _EditDealerPageState extends _EditDealerPageFields\n"
    + "    with\n"
    + "        _EditDealerPageStyle,\n"
    + "        _EditDealerPageHours,\n"
    + "        _EditDealerPageProfile,\n"
    + "        _EditDealerPageLocation,\n"
    + "        _EditDealerPageMedia,\n"
    + "        _EditDealerPageSave,\n"
    + "        _EditDealerPageBuild {}\n",
    encoding="utf-8",
)

(OUT / "edit_dealer_page_fields.dart").write_text(
    "part of 'edit_dealer_page.dart';\n\n"
    "const Color _editDealerAccent = Color(0xFFFF6B00);\n"
    "const int _editDealerMaxPhones = 5;\n"
    "const List<({String key, String label})> _editDealerDays = [\n"
    "  (key: 'sun', label: 'Sunday'),\n"
    "  (key: 'mon', label: 'Monday'),\n"
    "  (key: 'tue', label: 'Tuesday'),\n"
    "  (key: 'wed', label: 'Wednesday'),\n"
    "  (key: 'thu', label: 'Thursday'),\n"
    "  (key: 'fri', label: 'Friday'),\n"
    "  (key: 'sat', label: 'Saturday'),\n"
    "];\n\n"
    f"{day_hours_block}\n\n"
    "abstract class _EditDealerPageFields extends State<EditDealerPage> {\n"
    f"{fields_block}\n"
    "}\n",
    encoding="utf-8",
)

mixins = [
    ("edit_dealer_page_style.dart", "_EditDealerPageStyle", "_EditDealerPageFields", style_block),
    ("edit_dealer_page_hours.dart", "_EditDealerPageHours", "_EditDealerPageStyle", hours_block),
    ("edit_dealer_page_profile.dart", "_EditDealerPageProfile", "_EditDealerPageHours", profile_block),
    ("edit_dealer_page_location.dart", "_EditDealerPageLocation", "_EditDealerPageProfile", location_block),
    ("edit_dealer_page_media.dart", "_EditDealerPageMedia", "_EditDealerPageLocation", media_block),
    ("edit_dealer_page_save.dart", "_EditDealerPageSave", "_EditDealerPageMedia", save_block),
    ("edit_dealer_page_build.dart", "_EditDealerPageBuild", "_EditDealerPageSave", build_block),
]

for filename, mixin_name, on_name, body in mixins:
    (OUT / filename).write_text(
        f"part of 'edit_dealer_page.dart';\n\n"
        f"mixin {mixin_name} on {on_name} {{\n"
        f"{body.replace('_accent', '_editDealerAccent').replace('_maxPhones', '_editDealerMaxPhones').replace('_days', '_editDealerDays')}\n"
        "}\n",
        encoding="utf-8",
    )

print("Split edit_dealer_page into", len(parts), "parts")
