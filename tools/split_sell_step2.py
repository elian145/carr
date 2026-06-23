"""Split sell_step2.dart into fields + logic mixin."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
STEP2 = REPO / "lib/features/sell/sell_step2.dart"
FLOW = REPO / "lib/features/sell/sell_flow.dart"
lines = STEP2.read_text(encoding="utf-8").splitlines()


def find(substr: str, start: int = 0) -> int:
    for i in range(start, len(lines)):
        if substr in lines[i]:
            return i
    raise ValueError(substr)


widget_line = find("class SellStep2Page")
state_line = find("class _SellStep2PageState")
fields_start = find("final _formKey")
init_override = find("@override", fields_start)
did_update_override = find("@override", init_override + 1)
logic_start = find("CatalogSellFieldOptions? _computeCatalogSellOpts", did_update_override)
dispose_override = find("@override", logic_start)
save_draft_line = find("Future<void> _saveDraft()", dispose_override)
did_deps_override = find("@override", save_draft_line)
build_override = find("@override", did_deps_override)

fields_block = "\n".join(lines[fields_start:init_override])
init_block = "\n".join(lines[init_override:did_update_override])
did_update_block = "\n".join(lines[did_update_override:logic_start])
logic_block = "\n".join(
    lines[logic_start:dispose_override] + lines[save_draft_line:did_deps_override]
)
dispose_block = "\n".join(lines[dispose_override:save_draft_line])
did_deps_block = "\n".join(lines[did_deps_override:build_override])
build_block = "\n".join(lines[build_override:-1])  # drop closing class brace

widget_block = "\n".join(lines[widget_line:state_line])
out = REPO / "lib/features/sell"

(out / "sell_step2_fields.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    "abstract class _SellStep2Fields extends State<SellStep2Page> {\n"
    f"{fields_block}\n"
    "}\n",
    encoding="utf-8",
)

logic_text = logic_block.replace("_draftKey", "_SellStep2Fields._draftKey")
(out / "sell_step2_logic.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    "mixin _SellStep2Logic on _SellStep2Fields {\n"
    f"{logic_text}\n"
    "}\n",
    encoding="utf-8",
)

shell = (
    "part of 'sell_flow.dart';\n\n"
    f"{widget_block}\n"
    "class _SellStep2PageState extends _SellStep2Fields with _SellStep2Logic {\n"
    f"{init_block}\n"
    f"{did_update_block}\n"
    f"{dispose_block}\n"
    f"{did_deps_block}\n"
    f"{build_block}\n"
    "}\n"
)
STEP2.write_text(shell, encoding="utf-8")

flow_text = FLOW.read_text(encoding="utf-8")
if "sell_step2_fields.dart" not in flow_text:
    flow_text = flow_text.replace(
        "part 'sell_step2.dart';",
        "part 'sell_step2_fields.dart';\npart 'sell_step2_logic.dart';\npart 'sell_step2.dart';",
    )
    FLOW.write_text(flow_text, encoding="utf-8")

print("ok")
