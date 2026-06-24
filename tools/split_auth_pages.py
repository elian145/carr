"""Split auth_pages.dart into i18n helpers and three page parts."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/pages/auth_pages.dart"
OUT = REPO / "lib/pages"

lines = FILE.read_text(encoding="utf-8").splitlines()

login_start = next(i for i, line in enumerate(lines) if line.startswith("class LoginPage"))
register_start = next(i for i, line in enumerate(lines) if line.startswith("class RegisterPage"))
forgot_start = next(i for i, line in enumerate(lines) if line.startswith("class ForgotPasswordPage"))

imports = "\n".join(lines[:12]).rstrip()
i18n_block = "\n".join(lines[12:login_start]).rstrip()
login_block = "\n".join(lines[login_start:register_start]).rstrip()
register_block = "\n".join(lines[register_start:forgot_start]).rstrip()
forgot_block = "\n".join(lines[forgot_start:]).rstrip()

(FILE).write_text(
    imports
    + "\n\n"
    + "part 'auth_pages_i18n.dart';\n"
    + "part 'auth_login_page.dart';\n"
    + "part 'auth_register_page.dart';\n"
    + "part 'auth_forgot_password_page.dart';\n",
    encoding="utf-8",
)

(OUT / "auth_pages_i18n.dart").write_text(
    "part of 'auth_pages.dart';\n\n" + i18n_block + "\n",
    encoding="utf-8",
)

for name, block in (
    ("auth_login_page.dart", login_block),
    ("auth_register_page.dart", register_block),
    ("auth_forgot_password_page.dart", forgot_block),
):
    (OUT / name).write_text("part of 'auth_pages.dart';\n\n" + block + "\n", encoding="utf-8")

print(
    "Split auth_pages:",
    "i18n",
    len(i18n_block.splitlines()),
    "login",
    len(login_block.splitlines()),
    "register",
    len(register_block.splitlines()),
    "forgot",
    len(forgot_block.splitlines()),
)
