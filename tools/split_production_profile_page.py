"""Split production_profile_page.dart into style and body extension parts."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/pages/production_profile_page.dart"
ACCOUNT = REPO / "lib/pages/production_account_pages.dart"
OUT = REPO / "lib/pages"

lines = FILE.read_text(encoding="utf-8").splitlines()

part_of_end = next(i for i, line in enumerate(lines) if line.startswith("class ProfilePage"))
widget_start = part_of_end
state_start = next(i for i, line in enumerate(lines) if line.startswith("class _ProfilePageState"))
lifecycle_start = next(i for i, line in enumerate(lines) if line.strip() == "Map<String, dynamic>? me;")
logged_in_start = next(i for i, line in enumerate(lines) if line.strip().startswith("Widget _buildLoggedInState"))
widgets_start = next(i for i, line in enumerate(lines) if line.strip().startswith("Widget _buildInfoRow"))
build_start = next(i for i, line in enumerate(lines) if "Widget build(BuildContext context)" in line)
if build_start > 0 and lines[build_start - 1].strip() == "@override":
    build_start -= 1

part_header = "\n".join(lines[:widget_start]).rstrip()
widget_block = "\n".join(lines[widget_start:state_start]).rstrip()
style_block = "\n".join(lines[state_start + 1 : lifecycle_start]).rstrip()
lifecycle_block = "\n".join(lines[lifecycle_start:logged_in_start]).rstrip()
logged_in_block = "\n".join(lines[logged_in_start:widgets_start]).rstrip()
widgets_block = "\n".join(lines[widgets_start:build_start]).rstrip()
build_block = "\n".join(lines[build_start:-1]).rstrip()

(FILE).write_text(
    part_header
    + "\n\n"
    + widget_block
    + "\n\n"
    + "class _ProfilePageState extends State<ProfilePage> {\n"
    + lifecycle_block
    + "\n"
    + build_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "production_profile_style.dart").write_text(
    "part of 'production_account_pages.dart';\n\n"
    "extension _ProfilePageStyle on _ProfilePageState {\n"
    f"{style_block}\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "production_profile_body.dart").write_text(
    "part of 'production_account_pages.dart';\n\n"
    "extension _ProfilePageBody on _ProfilePageState {\n"
    f"{logged_in_block}\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "production_profile_widgets.dart").write_text(
    "part of 'production_account_pages.dart';\n\n"
    "extension _ProfilePageWidgets on _ProfilePageState {\n"
    f"{widgets_block}\n"
    "}\n",
    encoding="utf-8",
)

account = ACCOUNT.read_text(encoding="utf-8")
for part in (
    "part 'production_profile_style.dart';\n",
    "part 'production_profile_body.dart';\n",
    "part 'production_profile_widgets.dart';\n",
):
    if part not in account:
        account = account.replace(
            "part 'production_profile_page.dart';\n",
            part + "part 'production_profile_page.dart';\n",
        )
ACCOUNT.write_text(account, encoding="utf-8")

print(
    "Split production_profile:",
    len(style_block.splitlines()),
    len(logged_in_block.splitlines()),
    len(widgets_block.splitlines()),
)
