"""Split production_account_pages.dart into profile and settings parts."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/pages/production_account_pages.dart"
OUT = REPO / "lib/pages"

lines = FILE.read_text(encoding="utf-8").splitlines()

profile_start = next(i for i, line in enumerate(lines) if line.startswith("class ProfilePage"))
settings_start = next(i for i, line in enumerate(lines) if line.startswith("class SettingsPage"))

imports = "\n".join(lines[:profile_start]).rstrip()
profile_block = "\n".join(lines[profile_start:settings_start]).rstrip()
settings_block = "\n".join(lines[settings_start:]).rstrip()

(FILE).write_text(
    imports
    + "\n\n"
    + "part 'production_profile_page.dart';\n"
    + "part 'production_settings_page.dart';\n",
    encoding="utf-8",
)

(OUT / "production_profile_page.dart").write_text(
    "part of 'production_account_pages.dart';\n\n" + profile_block + "\n",
    encoding="utf-8",
)

(OUT / "production_settings_page.dart").write_text(
    "part of 'production_account_pages.dart';\n\n" + settings_block + "\n",
    encoding="utf-8",
)

print("Split production_account_pages:", len(profile_block.splitlines()), len(settings_block.splitlines()))
