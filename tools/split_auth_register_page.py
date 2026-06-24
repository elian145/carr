"""Split auth_register_page into fields, actions, and build mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/pages/auth_register_page.dart"
AUTH = REPO / "lib/pages/auth_pages.dart"
OUT = REPO / "lib/pages"

lines = FILE.read_text(encoding="utf-8").splitlines()

widget_start = next(i for i, line in enumerate(lines) if line.startswith("class RegisterPage"))
state_start = next(i for i, line in enumerate(lines) if line.startswith("class _RegisterPageState"))
dispose_start = next(
    i
    for i, line in enumerate(lines)
    if line.strip() == "@override" and i + 1 < len(lines) and "void dispose()" in lines[i + 1]
)
dispose_end = next(i for i in range(dispose_start, len(lines)) if "super.dispose();" in lines[i]) + 1
build_start = next(i for i, line in enumerate(lines) if "Widget build(BuildContext context)" in line)
if build_start > 0 and lines[build_start - 1].strip() == "@override":
    build_start -= 1

header = "\n".join(lines[:widget_start]).rstrip()
widget_block = "\n".join(lines[widget_start:state_start]).rstrip()
fields_block = "\n".join(lines[state_start + 1 : dispose_start]).rstrip()
dispose_block = "\n".join(lines[dispose_start:dispose_end + 1]).rstrip()
actions_block = "\n".join(lines[dispose_end + 1 : build_start]).rstrip()
build_block = "\n".join(lines[build_start:-1]).rstrip()

(OUT / "auth_register_page_fields.dart").write_text(
    "part of 'auth_pages.dart';\n\n"
    "abstract class _RegisterPageFields extends State<RegisterPage> {\n"
    + fields_block
    + "\n\n"
    + dispose_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "auth_register_page_actions.dart").write_text(
    "part of 'auth_pages.dart';\n\n"
    "mixin _RegisterPageActions on _RegisterPageFields {\n"
    + actions_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "auth_register_page_build.dart").write_text(
    "part of 'auth_pages.dart';\n\n"
    "mixin _RegisterPageBuild on _RegisterPageActions {\n"
    + build_block
    + "\n}\n",
    encoding="utf-8",
)

(FILE).write_text(
    header
    + "\n\n"
    + widget_block
    + "\n\n"
    + "class _RegisterPageState extends _RegisterPageFields\n"
    + "    with _RegisterPageActions, _RegisterPageBuild {}\n",
    encoding="utf-8",
)

auth = AUTH.read_text(encoding="utf-8")
for part_name in (
    "auth_register_page_fields.dart",
    "auth_register_page_actions.dart",
    "auth_register_page_build.dart",
):
    part = f"part '{part_name}';\n"
    if part not in auth:
        auth = auth.replace(
            "part 'auth_register_page.dart';\n",
            part + "part 'auth_register_page.dart';\n",
        )

AUTH.write_text(auth, encoding="utf-8")
print("Split auth_register_page")
