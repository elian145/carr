"""Split sell_car_page_draft.dart into persistence and banner mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FLOW = REPO / "lib/features/sell/sell_flow.dart"
DRAFT = REPO / "lib/features/sell/sell_car_page_draft.dart"
PAGE = REPO / "lib/features/sell/sell_car_page.dart"
OUT = REPO / "lib/features/sell"

lines = DRAFT.read_text(encoding="utf-8").splitlines()
banner_start = next(
    i for i, line in enumerate(lines) if line.strip().startswith("Widget _buildDraftBanner")
)

persist_block = "\n".join(lines[3:banner_start]).rstrip()
banner_block = "\n".join(lines[banner_start:-1]).rstrip()

(OUT / "sell_car_page_draft_persist.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    "mixin _SellCarPageDraftPersist on _SellCarPageFields {\n"
    + persist_block
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "sell_car_page_draft_banner.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    "mixin _SellCarPageDraftBanner on _SellCarPageDraftPersist {\n"
    + banner_block
    + "\n}\n",
    encoding="utf-8",
)

DRAFT.unlink(missing_ok=True)

flow = FLOW.read_text(encoding="utf-8")
flow = flow.replace(
    "part 'sell_car_page_draft.dart';\n",
    "part 'sell_car_page_draft_persist.dart';\n"
    "part 'sell_car_page_draft_banner.dart';\n",
)
FLOW.write_text(flow, encoding="utf-8")

page = PAGE.read_text(encoding="utf-8")
page = page.replace(
    "with _SellCarPageDraft {",
    "with _SellCarPageDraftPersist, _SellCarPageDraftBanner {",
)
PAGE.write_text(page, encoding="utf-8")

print("Split sell_car_page_draft")
