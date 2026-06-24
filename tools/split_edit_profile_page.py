"""Split edit_profile_page.dart into fields, style, load, widgets, and core mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/pages/edit_profile_page.dart"
OUT = REPO / "lib/pages"

lines = FILE.read_text(encoding="utf-8").splitlines()

top_level_end = next(i for i, line in enumerate(lines) if line.startswith("class EditProfilePage"))
get_api_block = "\n".join(lines[top_level_end - 4 : top_level_end]).rstrip()
# getApiBase is 4 lines before EditProfilePage (blank + function)
if "getApiBase" not in get_api_block:
    get_api_start = next(i for i, line in enumerate(lines) if line.startswith("String getApiBase"))
    get_api_end = next(i for i in range(get_api_start, len(lines)) if lines[i].strip() == "}")
    get_api_block = "\n".join(lines[get_api_start : get_api_end + 1]).rstrip()

import_end = next(
    i for i, line in enumerate(lines)
    if line.strip() and not line.startswith("import") and not line.startswith("//")
)
header = "\n".join(lines[:import_end]).rstrip()

widget_start = top_level_end
state_start = next(i for i, line in enumerate(lines) if line.startswith("class _EditProfilePageState"))
init_start = next(
    i
    for i, line in enumerate(lines)
    if line.strip() == "@override" and i + 1 < len(lines) and "void initState()" in lines[i + 1]
)
dispose_start = next(
    i
    for i, line in enumerate(lines)
    if line.strip() == "@override" and i + 1 < len(lines) and "void dispose()" in lines[i + 1]
)
dispose_end = next(i for i in range(dispose_start, len(lines)) if "super.dispose();" in lines[i]) + 1
style_start = next(i for i, line in enumerate(lines) if line.strip().startswith("bool _shellLight"))
load_start = next(i for i, line in enumerate(lines) if line.strip().startswith("Future<void> _loadUserData"))
widgets_start = next(i for i, line in enumerate(lines) if line.strip().startswith("Widget _buildProfileImageSection"))
build_start = next(i for i, line in enumerate(lines) if "Widget build(BuildContext context)" in line)
if build_start > 0 and lines[build_start - 1].strip() == "@override":
    build_start -= 1

widget_block = "\n".join(lines[widget_start:state_start]).rstrip()
fields_block = "\n".join(lines[state_start + 1 : init_start] + lines[dispose_start : dispose_end + 1]).rstrip()
style_block = "\n".join(lines[style_start:load_start]).rstrip()
load_block = "\n".join(lines[init_start:dispose_start] + lines[load_start:widgets_start]).rstrip()
widgets_block = "\n".join(lines[widgets_start:build_start]).rstrip()
core_block = "\n".join(lines[build_start:-1]).rstrip()

(FILE).write_text(
    header
    + "\n\n"
    + "part 'edit_profile_page_fields.dart';\n"
    + "part 'edit_profile_page_style.dart';\n"
    + "part 'edit_profile_page_load.dart';\n"
    + "part 'edit_profile_page_widgets.dart';\n"
    + "part 'edit_profile_page_core.dart';\n\n"
    + get_api_block
    + "\n\n"
    + widget_block
    + "\n\n"
    + "class _EditProfilePageState extends _EditProfilePageFields\n"
    + "    with\n"
    + "        _EditProfilePageStyle,\n"
    + "        _EditProfilePageLoad,\n"
    + "        _EditProfilePageWidgets,\n"
    + "        _EditProfilePageCore {}\n",
    encoding="utf-8",
)

(OUT / "edit_profile_page_fields.dart").write_text(
    "part of 'edit_profile_page.dart';\n\n"
    "abstract class _EditProfilePageFields extends State<EditProfilePage> {\n"
    + fields_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "edit_profile_page_style.dart").write_text(
    "part of 'edit_profile_page.dart';\n\n"
    "mixin _EditProfilePageStyle on _EditProfilePageFields {\n"
    + style_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "edit_profile_page_load.dart").write_text(
    "part of 'edit_profile_page.dart';\n\n"
    "mixin _EditProfilePageLoad on _EditProfilePageStyle {\n"
    + load_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "edit_profile_page_widgets.dart").write_text(
    "part of 'edit_profile_page.dart';\n\n"
    "mixin _EditProfilePageWidgets on _EditProfilePageLoad {\n"
    + widgets_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "edit_profile_page_core.dart").write_text(
    "part of 'edit_profile_page.dart';\n\n"
    "mixin _EditProfilePageCore on _EditProfilePageWidgets {\n"
    + core_block
    + "\n}\n",
    encoding="utf-8",
)

print("Split edit_profile_page")
