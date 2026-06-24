"""Split global_listing_card.dart into labels, inner text, carousel, and build parts."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/app/widgets/global_listing_card.dart"
OUT = REPO / "lib/app/widgets"

lines = FILE.read_text(encoding="utf-8").splitlines()

import_end = next(i for i, line in enumerate(lines) if line.startswith("/// Localized car"))
video_start = next(i for i, line in enumerate(lines) if line.startswith("/// Video count pill"))
inner_start = next(i for i, line in enumerate(lines) if line.startswith("/// Title / price"))
build_start = next(i for i, line in enumerate(lines) if line.startswith("// Global car card"))
carousel_start = next(i for i, line in enumerate(lines) if line.startswith("// Global image carousel"))

imports = "\n".join(lines[:import_end]).rstrip()
labels = "\n".join(lines[import_end:video_start]).rstrip()
video_badge = "\n".join(lines[video_start:inner_start]).rstrip()
inner_text = "\n".join(lines[inner_start:build_start]).rstrip()
build_block = "\n".join(lines[build_start:carousel_start]).rstrip()
carousel_block = "\n".join(lines[carousel_start:]).rstrip()

(FILE).write_text(
    imports
    + "\n\n"
    + "part 'global_listing_card_inner_text.dart';\n"
    + "part 'global_listing_card_carousel.dart';\n"
    + "part 'global_listing_card_build.dart';\n\n"
    + labels
    + "\n",
    encoding="utf-8",
)

(OUT / "global_listing_card_inner_text.dart").write_text(
    "part of 'global_listing_card.dart';\n\n" + inner_text + "\n",
    encoding="utf-8",
)

(OUT / "global_listing_card_carousel.dart").write_text(
    "part of 'global_listing_card.dart';\n\n" + video_badge + "\n\n" + carousel_block + "\n",
    encoding="utf-8",
)

(OUT / "global_listing_card_build.dart").write_text(
    "part of 'global_listing_card.dart';\n\n" + build_block + "\n",
    encoding="utf-8",
)

print("Split global_listing_card -> inner_text, carousel, build")
