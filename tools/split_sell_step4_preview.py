"""Split sell_step4_preview.dart into listing widget and review scroll view."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PREVIEW = REPO / "lib/features/sell/sell_step4_preview.dart"
FLOW = REPO / "lib/features/sell/sell_flow.dart"
OUT = REPO / "lib/features/sell"

lines = PREVIEW.read_text(encoding="utf-8").splitlines()
split = next(i for i, line in enumerate(lines) if line.startswith("String _sellReviewListingBrand"))

listing_block = "\n".join(lines[1:split] if lines[0].strip().startswith("part of") else lines[:split]).rstrip()
review_block = "\n".join(lines[split:]).rstrip()

(OUT / "sell_step4_preview_listing.dart").write_text(
    "part of 'sell_flow.dart';\n\n" + listing_block + "\n",
    encoding="utf-8",
)

(OUT / "sell_step4_preview_review.dart").write_text(
    "part of 'sell_flow.dart';\n\n" + review_block + "\n",
    encoding="utf-8",
)

PREVIEW.unlink()

flow = FLOW.read_text(encoding="utf-8")
flow = flow.replace(
    "part 'sell_step4_preview.dart';",
    "part 'sell_step4_preview_listing.dart';\npart 'sell_step4_preview_review.dart';",
)
FLOW.write_text(flow, encoding="utf-8")
print("listing", len(listing_block.splitlines()), "review", len(review_block.splitlines()))
