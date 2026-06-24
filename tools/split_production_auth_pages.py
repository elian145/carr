"""Split production_auth_pages.dart into one part per page."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/pages/production_auth_pages.dart"
OUT = REPO / "lib/pages"

lines = FILE.read_text(encoding="utf-8").splitlines()

favorites_start = next(i for i, line in enumerate(lines) if line.startswith("class FavoritesPage"))
chat_start = next(i for i, line in enumerate(lines) if line.startswith("class ChatListPage"))
login_start = next(i for i, line in enumerate(lines) if line.startswith("class LoginPage"))
signup_start = next(i for i, line in enumerate(lines) if line.startswith("class SignupPage"))

imports = "\n".join(lines[:favorites_start]).rstrip()
favorites_block = "\n".join(lines[favorites_start:chat_start]).rstrip()
chat_block = "\n".join(lines[chat_start:login_start]).rstrip()
login_block = "\n".join(lines[login_start:signup_start]).rstrip()
signup_block = "\n".join(lines[signup_start:]).rstrip()

(FILE).write_text(
    imports
    + "\n\n"
    + "part 'production_favorites_page.dart';\n"
    + "part 'production_chat_list_page.dart';\n"
    + "part 'production_login_page.dart';\n"
    + "part 'production_signup_page.dart';\n",
    encoding="utf-8",
)

for name, block in (
    ("production_favorites_page.dart", favorites_block),
    ("production_chat_list_page.dart", chat_block),
    ("production_login_page.dart", login_block),
    ("production_signup_page.dart", signup_block),
):
    (OUT / name).write_text("part of 'production_auth_pages.dart';\n\n" + block + "\n", encoding="utf-8")

print(
    "Split production_auth_pages:",
    len(favorites_block.splitlines()),
    len(chat_block.splitlines()),
    len(login_block.splitlines()),
    len(signup_block.splitlines()),
)
