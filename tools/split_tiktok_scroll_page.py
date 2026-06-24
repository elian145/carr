"""Split tiktok_scroll_page.dart into shell and listing card part."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/pages/tiktok_scroll_page.dart"
OUT = REPO / "lib/pages"

lines = FILE.read_text(encoding="utf-8").splitlines()

card_start = next(i for i, line in enumerate(lines) if line.startswith("class _TikTokListingCard"))
first_class = next(i for i, line in enumerate(lines) if line.startswith("class "))
header = "\n".join(lines[:first_class]).rstrip()
shell = "\n".join(lines[first_class:card_start]).rstrip()
card_block = "\n".join(lines[card_start:]).rstrip()

(FILE).write_text(
    header
    + "\n\n"
    + "part 'tiktok_scroll_listing_card.dart';\n\n"
    + shell
    + "\n",
    encoding="utf-8",
)

(OUT / "tiktok_scroll_listing_card.dart").write_text(
    "part of 'tiktok_scroll_page.dart';\n\n" + card_block + "\n",
    encoding="utf-8",
)

print("Split tiktok_scroll_page")
