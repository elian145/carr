"""Split sell_car_page.dart into fields, draft mixin, and shell state."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PAGE = REPO / "lib/features/sell/sell_car_page.dart"
FLOW = REPO / "lib/features/sell/sell_flow.dart"
OUT = REPO / "lib/features/sell"

lines = PAGE.read_text(encoding="utf-8").splitlines()

widget_end = next(i for i, line in enumerate(lines) if line.startswith("class _SellCarPageState"))
state_fields_end = next(
    i for i, line in enumerate(lines) if "bool _sellPersistFieldNonEmpty" in line
)
draft_end = next(
    i
    for i, line in enumerate(lines)
    if line.strip() == "void initState() {" and i > 0 and "@override" in lines[i - 1]
)

widget_block = "\n".join(
    line for line in lines[:widget_end]
    if not line.strip().startswith("part of")
).rstrip()
fields_block = "\n".join(lines[widget_end + 1 : state_fields_end]).rstrip()
draft_block = "\n".join(lines[state_fields_end:draft_end]).rstrip()
shell_block = "\n".join(lines[draft_end:]).rstrip()

(OUT / "sell_car_page_fields.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    "abstract class _SellCarPageFields extends State<SellCarPage> {\n"
    f"{fields_block}\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "sell_car_page_draft.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    "mixin _SellCarPageDraft on _SellCarPageFields {\n"
    f"{draft_block}\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "sell_car_page.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    f"{widget_block}\n\n"
    "class _SellCarPageState extends _SellCarPageFields with _SellCarPageDraft {\n"
    f"{shell_block}\n"
    "}\n",
    encoding="utf-8",
)

flow = FLOW.read_text(encoding="utf-8")
for part in ("sell_car_page_fields.dart", "sell_car_page_draft.dart"):
    if f"part '{part}'" not in flow:
        flow = flow.replace(
            "part 'sell_car_page.dart';",
            f"part '{part}';\npart 'sell_car_page.dart';",
        )
FLOW.write_text(flow, encoding="utf-8")
print("fields", len(fields_block.splitlines()), "draft", len(draft_block.splitlines()))
