"""Split production_signup_page into fields, actions, and build mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/pages/production_signup_page.dart"
AUTH = REPO / "lib/pages/production_auth_pages.dart"
OUT = REPO / "lib/pages"

lines = FILE.read_text(encoding="utf-8").splitlines()

widget_start = next(i for i, line in enumerate(lines) if line.startswith("class SignupPage"))
state_start = next(i for i, line in enumerate(lines) if line.startswith("class _SignupPageState"))
dispose_start = next(i for i, line in enumerate(lines) if line.strip() == "@override" and i + 1 < len(lines) and "void dispose()" in lines[i + 1])
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

(OUT / "production_signup_page_fields.dart").write_text(
    "part of 'production_auth_pages.dart';\n\n"
    "abstract class _SignupPageFields extends State<SignupPage> {\n"
    + fields_block
    + "\n\n"
    + dispose_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "production_signup_page_actions.dart").write_text(
    "part of 'production_auth_pages.dart';\n\n"
    "mixin _SignupPageActions on _SignupPageFields {\n"
    + actions_block
    + "\n}\n",
    encoding="utf-8",
)

(FILE).write_text(
    header
    + "\n\n"
    + widget_block
    + "\n\n"
    + "class _SignupPageState extends _SignupPageFields\n"
    + "    with _SignupPageActions, _SignupPageBuild {}\n",
    encoding="utf-8",
)

(OUT / "production_signup_page_build.dart").write_text(
    "part of 'production_auth_pages.dart';\n\n"
    "mixin _SignupPageBuild on _SignupPageActions {\n"
    f"{build_block}\n"
    "}\n",
    encoding="utf-8",
)

auth = AUTH.read_text(encoding="utf-8")
for part_name in [
    "production_signup_page_fields.dart",
    "production_signup_page_actions.dart",
    "production_signup_page_build.dart",
]:
    part = f"part '{part_name}';\n"
    if part not in auth:
        auth = auth.replace(
            "part 'production_signup_page.dart';\n",
            part + "part 'production_signup_page.dart';\n",
        )

AUTH.write_text(auth, encoding="utf-8")
print("Split production_signup_page")
