"""Split sell_step1.dart into fields + logic mixin."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
STEP1 = REPO / "lib/features/sell/sell_step1.dart"
FLOW = REPO / "lib/features/sell/sell_flow.dart"
lines = STEP1.read_text(encoding="utf-8").splitlines()


def find(substr: str, start: int = 0) -> int:
    for i in range(start, len(lines)):
        if substr in lines[i]:
            return i
    raise ValueError(substr)


def method_end(start: int) -> int:
    depth = 0
    opened = False
    for i in range(start, len(lines)):
        for ch in lines[i]:
            if ch == "{":
                depth += 1
                opened = True
            elif ch == "}":
                depth -= 1
                if opened and depth == 0:
                    return i + 1
    raise ValueError(f"method end not found from line {start + 1}")


widget_line = find("class SellStep1Page")
state_line = find("class _SellStep1PageState")
fields_start = find("final _formKey")
logic_start = find("String _brandSlug(String brand) {", fields_start)
init_override = find("@override", logic_start)
did_update_override = find("@override", init_override + 1)
dispose_override = find("@override", did_update_override + 1)
dispose_end = method_end(dispose_override)
build_override = find("@override", dispose_end)

fields_block = "\n".join(lines[fields_start:logic_start])
init_block = "\n".join(lines[init_override:did_update_override])
did_update_block = "\n".join(lines[did_update_override:dispose_override])
dispose_block = "\n".join(lines[dispose_override:dispose_end])
logic_block = "\n".join(lines[logic_start:init_override] + lines[dispose_end:build_override])
build_end = method_end(build_override)
build_block = "\n".join(lines[build_override:build_end])

widget_block = "\n".join(lines[widget_line:state_line])
out = REPO / "lib/features/sell"

(out / "sell_step1_fields.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    "abstract class _SellStep1Fields extends State<SellStep1Page> {\n"
    f"{fields_block}\n"
    "}\n",
    encoding="utf-8",
)

logic_text = logic_block.replace("_draftKey", "_SellStep1Fields._draftKey")
(out / "sell_step1_logic.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    "mixin _SellStep1Logic on _SellStep1Fields {\n"
    f"{logic_text}\n"
    "}\n",
    encoding="utf-8",
)

shell = (
    "part of 'sell_flow.dart';\n\n"
    f"{widget_block}\n"
    "class _SellStep1PageState extends _SellStep1Fields with _SellStep1Logic {\n"
    f"{init_block}\n"
    f"{did_update_block}\n"
    f"{dispose_block}\n"
    f"{build_block}\n"
    "}\n"
)
STEP1.write_text(shell, encoding="utf-8")

flow_text = FLOW.read_text(encoding="utf-8")
if "sell_step1_fields.dart" not in flow_text:
    flow_text = flow_text.replace(
        "part 'sell_step1.dart';",
        "part 'sell_step1_fields.dart';\npart 'sell_step1_logic.dart';\npart 'sell_step1.dart';",
    )
    FLOW.write_text(flow_text, encoding="utf-8")

print("logic", len(logic_text.splitlines()), "shell", len(shell.splitlines()))
