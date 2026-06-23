"""Split sell step N body mixin into fields + logic mixins."""
from __future__ import annotations

import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
STEP = int(sys.argv[1]) if len(sys.argv) > 1 else 3
STEP_FILE = REPO / f"lib/features/sell/sell_step{STEP}.dart"
FLOW = REPO / "lib/features/sell/sell_flow.dart"
BUILD_FILE = REPO / f"lib/features/sell/sell_step{STEP}_build.dart"

LOGIC_START = {
    3: "String _convertCurrency(",
    4: "void initState()",
}

fields_mixin = f"_SellStep{STEP}Fields"
logic_mixin = f"_SellStep{STEP}Logic"
body_mixin = f"_SellStep{STEP}Body"
build_mixin = f"_SellStep{STEP}Build"


def find(substr: str, lines: list[str], start: int = 0) -> int:
    for i in range(start, len(lines)):
        if substr in lines[i]:
            return i
    raise ValueError(substr)


lines = STEP_FILE.read_text(encoding="utf-8").splitlines()
body_line = find(f"mixin {body_mixin}", lines)
body_open = body_line + 1
body_close = find("class _SellStep", lines, body_line + 1)
while body_close > body_open and lines[body_close - 1].strip() in ("", "}"):
    body_close -= 1
body_lines = lines[body_open:body_close]

logic_marker = LOGIC_START[STEP]
logic_start = find(logic_marker, body_lines)
fields_block = "\n".join(body_lines[:logic_start]).rstrip()
logic_block = "\n".join(body_lines[logic_start:]).rstrip()

logic_block = logic_block.replace("_draftKey", f"{fields_mixin}._draftKey")
if STEP == 3:
    logic_block = logic_block.replace(
        "_pricePickerNoneOption",
        f"{fields_mixin}._pricePickerNoneOption",
    )

out = REPO / "lib/features/sell"
(out / f"sell_step{STEP}_fields.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    f"mixin {fields_mixin} on State<SellStep{STEP}Page> {{\n"
    f"{fields_block}\n"
    "}\n",
    encoding="utf-8",
)
(out / f"sell_step{STEP}_logic.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    f"mixin {logic_mixin} on {fields_mixin} {{\n"
    f"{logic_block}\n"
    "}\n",
    encoding="utf-8",
)

shell = (
    "\n".join(lines[:body_line])
    + f"\nclass _SellStep{STEP}PageState extends State<SellStep{STEP}Page>\n"
    + f"    with {fields_mixin}, {logic_mixin}, {build_mixin} {{}}\n"
)
STEP_FILE.write_text(shell, encoding="utf-8")

if BUILD_FILE.exists():
    build_text = BUILD_FILE.read_text(encoding="utf-8")
    build_text = build_text.replace(f"on {body_mixin}", f"on {logic_mixin}")
    BUILD_FILE.write_text(build_text, encoding="utf-8")

flow = FLOW.read_text(encoding="utf-8")
if f"sell_step{STEP}_fields.dart" not in flow:
    flow = flow.replace(
        f"part 'sell_step{STEP}.dart';",
        f"part 'sell_step{STEP}_fields.dart';\n"
        f"part 'sell_step{STEP}_logic.dart';\n"
        f"part 'sell_step{STEP}.dart';",
    )
FLOW.write_text(flow, encoding="utf-8")

print(
    "fields",
    len(fields_block.splitlines()),
    "logic",
    len(logic_block.splitlines()),
)
