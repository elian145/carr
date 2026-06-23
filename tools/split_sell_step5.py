"""Split monolithic sell step 5 into fields, logic, and build."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
STEP_FILE = REPO / "lib/features/sell/sell_step5.dart"
BUILD_FILE = REPO / "lib/features/sell/sell_step5_build.dart"
FLOW = REPO / "lib/features/sell/sell_flow.dart"
lines = STEP_FILE.read_text(encoding="utf-8").splitlines()


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


state_line = find("class _SellStep5PageState")
build_line = find("Widget build(BuildContext context)", state_line)
build_end = method_end(build_line)
logic_line = find("Map<String, dynamic> _buildCarUpdatePayload", state_line)
logic_end = len(lines)
while logic_end > logic_line and lines[logic_end - 1].strip() in ("", "}"):
    logic_end -= 1

fields_block = "\n".join(lines[state_line + 1 : build_line - 1]).rstrip()
logic_block = "\n".join(lines[logic_line:logic_end]).rstrip()
build_block = "\n".join(lines[build_line - 1 : build_end])
widget_block = "\n".join(lines[:state_line])

out = REPO / "lib/features/sell"
(out / "sell_step5_fields.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    "mixin _SellStep5Fields on State<SellStep5Page> {\n"
    f"{fields_block}\n"
    "}\n",
    encoding="utf-8",
)
(out / "sell_step5_logic.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    "mixin _SellStep5Logic on _SellStep5Fields {\n"
    f"{logic_block}\n"
    "}\n",
    encoding="utf-8",
)
BUILD_FILE.write_text(
    "part of 'sell_flow.dart';\n\n"
    "mixin _SellStep5Build on _SellStep5Logic {\n"
    f"{build_block}\n"
    "}\n",
    encoding="utf-8",
)
STEP_FILE.write_text(
    f"{widget_block}\n"
    "class _SellStep5PageState extends State<SellStep5Page>\n"
    "    with _SellStep5Fields, _SellStep5Logic, _SellStep5Build {}\n",
    encoding="utf-8",
)

flow = FLOW.read_text(encoding="utf-8")
if "sell_step5_fields.dart" not in flow:
    flow = flow.replace(
        "part 'sell_step5.dart';",
        "part 'sell_step5_fields.dart';\n"
        "part 'sell_step5_logic.dart';\n"
        "part 'sell_step5_build.dart';\n"
        "part 'sell_step5.dart';",
    )
    FLOW.write_text(flow, encoding="utf-8")

print("fields", len(fields_block.splitlines()), "logic", len(logic_block.splitlines()))
