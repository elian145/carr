"""Split forgot_password_page.dart into fields, labels, actions, and core mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/pages/forgot_password_page.dart"
OUT = REPO / "lib/pages"

lines = FILE.read_text(encoding="utf-8").splitlines()

import_end = next(
    i
    for i, line in enumerate(lines)
    if line.strip() and not line.startswith("import") and not line.startswith("//")
)
header = "\n".join(lines[:import_end]).rstrip()

widget_start = next(i for i, line in enumerate(lines) if line.startswith("class ForgotPasswordPage"))
state_start = next(i for i, line in enumerate(lines) if line.startswith("class _ForgotPasswordPageState"))
dispose_start = next(
    i
    for i, line in enumerate(lines)
    if line.strip() == "@override" and i + 1 < len(lines) and "void dispose()" in lines[i + 1]
)
dispose_end = next(i for i in range(dispose_start, len(lines)) if "super.dispose();" in lines[i]) + 1
labels_start = next(
    i for i, line in enumerate(lines) if line.strip().startswith("String _forgotPasswordTitle")
)
actions_start = next(i for i, line in enumerate(lines) if line.strip().startswith("Future<void> _sendReset"))
build_start = next(i for i, line in enumerate(lines) if "Widget build(BuildContext context)" in line)
if build_start > 0 and lines[build_start - 1].strip() == "@override":
    build_start -= 1

widget_block = "\n".join(lines[widget_start:state_start]).rstrip()
fields_block = "\n".join(lines[state_start + 1 : dispose_start] + lines[dispose_start : dispose_end + 1]).rstrip()
labels_block = "\n".join(lines[labels_start:actions_start]).rstrip()
actions_block = "\n".join(lines[actions_start:build_start]).rstrip()
core_block = "\n".join(lines[build_start:-1]).rstrip()

(FILE).write_text(
    header
    + "\n\n"
    + "part 'forgot_password_page_fields.dart';\n"
    + "part 'forgot_password_page_labels.dart';\n"
    + "part 'forgot_password_page_actions.dart';\n"
    + "part 'forgot_password_page_core.dart';\n\n"
    + widget_block
    + "\n\n"
    + "class _ForgotPasswordPageState extends _ForgotPasswordPageFields\n"
    + "    with\n"
    + "        _ForgotPasswordPageLabels,\n"
    + "        _ForgotPasswordPageActions,\n"
    + "        _ForgotPasswordPageCore {}\n",
    encoding="utf-8",
)

(OUT / "forgot_password_page_fields.dart").write_text(
    "part of 'forgot_password_page.dart';\n\n"
    "abstract class _ForgotPasswordPageFields extends State<ForgotPasswordPage> {\n"
    + fields_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "forgot_password_page_labels.dart").write_text(
    "part of 'forgot_password_page.dart';\n\n"
    "mixin _ForgotPasswordPageLabels on _ForgotPasswordPageFields {\n"
    + labels_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "forgot_password_page_actions.dart").write_text(
    "part of 'forgot_password_page.dart';\n\n"
    "mixin _ForgotPasswordPageActions on _ForgotPasswordPageLabels {\n"
    + actions_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "forgot_password_page_core.dart").write_text(
    "part of 'forgot_password_page.dart';\n\n"
    "mixin _ForgotPasswordPageCore on _ForgotPasswordPageActions {\n"
    + core_block
    + "\n}\n",
    encoding="utf-8",
)

print("Split forgot_password_page")
