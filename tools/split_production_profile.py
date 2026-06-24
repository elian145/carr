"""Split production profile page into fields, mixins, and body sections."""
from __future__ import annotations

import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
ACCOUNT = REPO / "lib/pages/production_account_pages.dart"
PAGE = REPO / "lib/pages/production_profile_page.dart"
STYLE = REPO / "lib/pages/production_profile_style.dart"
WIDGETS = REPO / "lib/pages/production_profile_widgets.dart"
BODY = REPO / "lib/pages/production_profile_body.dart"
OUT = REPO / "lib/pages"


def normalize_indent(lines: list[str], target: int = 6) -> str:
    nonempty = [line for line in lines if line.strip()]
    min_indent = min(len(line) - len(line.lstrip()) for line in nonempty)
    return "\n".join(
        ((" " * target) + line[min_indent:]) if line.strip() else ""
        for line in lines
    ).rstrip()


def line_indent(line: str) -> int:
    return len(line) - len(line.lstrip())


def mixin_from_extension(text: str, mixin_name: str, on_type: str) -> str:
    text = re.sub(
        rf"extension {mixin_name} on _ProfilePageState",
        f"mixin {mixin_name} on {on_type}",
        text,
        count=1,
    )
    return text


page_lines = PAGE.read_text(encoding="utf-8").splitlines()
style_text = STYLE.read_text(encoding="utf-8")
widgets_text = WIDGETS.read_text(encoding="utf-8")
body_lines = BODY.read_text(encoding="utf-8").splitlines()

widget_start = next(i for i, line in enumerate(page_lines) if line.startswith("class ProfilePage"))
state_start = next(i for i, line in enumerate(page_lines) if line.startswith("class _ProfilePageState"))
init_start = next(
    i
    for i, line in enumerate(page_lines)
    if line.strip() == "@override" and i + 1 < len(page_lines) and "void initState()" in page_lines[i + 1]
)
build_start = next(i for i, line in enumerate(page_lines) if "Widget build(BuildContext context)" in line)
if build_start > 0 and page_lines[build_start - 1].strip() == "@override":
    build_start -= 1

account_lines = ACCOUNT.read_text(encoding="utf-8").splitlines()
part_line = next(i for i, line in enumerate(account_lines) if line.startswith("part "))
header = "\n".join(account_lines[:part_line]).rstrip()

widget_block = "\n".join(page_lines[widget_start:state_start]).rstrip()
fields_block = "\n".join(page_lines[state_start + 1 : init_start]).rstrip()
load_block = "\n".join(page_lines[init_start:build_start]).rstrip()
core_block = "\n".join(page_lines[build_start:-1]).rstrip()

guest_start = next(i for i, line in enumerate(body_lines) if line.strip() == "if (!isLoggedIn) ...[")
account_start = next(i for i, line in enumerate(body_lines) if line.strip() == "if (isLoggedIn) ...[")
actions_start = next(i for i, line in enumerate(body_lines) if "// Action Buttons" in line)
account_end = actions_start - 1
while account_end > account_start and not body_lines[account_end].strip():
    account_end -= 1
if body_lines[account_end].strip() == "],":
    account_end -= 1
actions_end = next(
    i
    for i in range(actions_start, len(body_lines))
    if body_lines[i].strip() == "],"
    and line_indent(body_lines[i]) == 14
    and i + 1 < len(body_lines)
    and body_lines[i + 1].strip() == "],"
    and line_indent(body_lines[i + 1]) == 12
)

guest_block = normalize_indent(body_lines[guest_start + 1 : account_start - 1])
account_block = normalize_indent(body_lines[account_start + 1 : account_end + 1])
actions_block = normalize_indent(body_lines[actions_start : actions_end + 1])

shell_block = """  Widget _buildLoggedInState(BuildContext context) {
    final profile = _effectiveProfile();
    final isLoggedIn =
        ApiService.accessToken != null && ApiService.accessToken!.isNotEmpty;
    final isLightShell = _profileLightShell(context);
    return Stack(
      children: [
        Container(decoration: _shellDecoration(context)),
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
          child: Column(
            children: [
              if (!isLoggedIn) ..._buildProfileGuestSection(context),
              if (isLoggedIn)
                ..._buildProfileAccountSection(context, profile, isLightShell),
              ..._buildProfileActionsSection(context, profile, isLoggedIn),
            ],
          ),
        ),
      ],
    );
  }"""

parts = [
    "production_profile_fields.dart",
    "production_profile_style.dart",
    "production_profile_load.dart",
    "production_profile_widgets.dart",
    "production_profile_body_guest.dart",
    "production_profile_body_account.dart",
    "production_profile_body_actions.dart",
    "production_profile_body.dart",
    "production_profile_core.dart",
    "production_profile_page.dart",
    "production_settings_page.dart",
]

parts_block = "\n".join(f"part '{name}';" for name in parts)

(ACCOUNT).write_text(
    header + "\n" + parts_block + "\n",
    encoding="utf-8",
)

(PAGE).write_text(
    "part of 'production_account_pages.dart';\n\n"
    + widget_block
    + "\n\n"
    + "class _ProfilePageState extends _ProfilePageFields\n"
    + "    with\n"
    + "        _ProfilePageStyle,\n"
    + "        _ProfilePageLoad,\n"
    + "        _ProfilePageWidgets,\n"
    + "        _ProfilePageBodyGuest,\n"
    + "        _ProfilePageBodyAccount,\n"
    + "        _ProfilePageBodyActions,\n"
    + "        _ProfilePageBody {}\n",
    encoding="utf-8",
)

(OUT / "production_profile_fields.dart").write_text(
    "part of 'production_account_pages.dart';\n\n"
    "abstract class _ProfilePageFields extends State<ProfilePage> {\n"
    + fields_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "production_profile_load.dart").write_text(
    "part of 'production_account_pages.dart';\n\n"
    "mixin _ProfilePageLoad on _ProfilePageStyle {\n"
    + load_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "production_profile_core.dart").write_text(
    "part of 'production_account_pages.dart';\n\n"
    "mixin _ProfilePageCore on _ProfilePageBody {\n"
    + core_block
    + "\n}\n",
    encoding="utf-8",
)

STYLE.write_text(
    mixin_from_extension(style_text, "_ProfilePageStyle", "_ProfilePageFields"),
    encoding="utf-8",
)

WIDGETS.write_text(
    mixin_from_extension(widgets_text, "_ProfilePageWidgets", "_ProfilePageLoad"),
    encoding="utf-8",
)

(OUT / "production_profile_body_guest.dart").write_text(
    "part of 'production_account_pages.dart';\n\n"
    "mixin _ProfilePageBodyGuest on _ProfilePageWidgets {\n"
    "  List<Widget> _buildProfileGuestSection(BuildContext context) {\n"
    "    return [\n"
    + guest_block
    + "\n    ];\n"
    "  }\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "production_profile_body_account.dart").write_text(
    "part of 'production_account_pages.dart';\n\n"
    "mixin _ProfilePageBodyAccount on _ProfilePageBodyGuest {\n"
    "  List<Widget> _buildProfileAccountSection(\n"
    "    BuildContext context,\n"
    "    Map<String, dynamic>? profile,\n"
    "    bool isLightShell,\n"
    "  ) {\n"
    "    return [\n"
    + account_block
    + "\n    ];\n"
    "  }\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "production_profile_body_actions.dart").write_text(
    "part of 'production_account_pages.dart';\n\n"
    "mixin _ProfilePageBodyActions on _ProfilePageBodyAccount {\n"
    "  List<Widget> _buildProfileActionsSection(\n"
    "    BuildContext context,\n"
    "    Map<String, dynamic>? profile,\n"
    "    bool isLoggedIn,\n"
    "  ) {\n"
    "    return [\n"
    + actions_block
    + "\n    ];\n"
    "  }\n"
    "}\n",
    encoding="utf-8",
)

(BODY).write_text(
    "part of 'production_account_pages.dart';\n\n"
    "mixin _ProfilePageBody on _ProfilePageBodyActions {\n"
    + shell_block
    + "\n}\n",
    encoding="utf-8",
)

page_text = PAGE.read_text(encoding="utf-8")
page_text = page_text.replace(
    "        _ProfilePageBody {}",
    "        _ProfilePageBody,\n        _ProfilePageCore {}",
)
PAGE.write_text(page_text, encoding="utf-8")

print("Split production_profile")
