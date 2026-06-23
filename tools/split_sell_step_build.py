"""Extract sell step N build method into sell_stepN_build.dart mixin."""
from __future__ import annotations

import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
STEP = int(sys.argv[1]) if len(sys.argv) > 1 else 1
STEP_FILE = REPO / f"lib/features/sell/sell_step{STEP}.dart"
BUILD_FILE = REPO / f"lib/features/sell/sell_step{STEP}_build.dart"
FLOW = REPO / "lib/features/sell/sell_flow.dart"
LOGIC_FILE = REPO / f"lib/features/sell/sell_step{STEP}_logic.dart"

lines = STEP_FILE.read_text(encoding="utf-8").splitlines()
state_marker = f"class _SellStep{STEP}PageState"
logic_mixin = f"_SellStep{STEP}Logic"
body_mixin = f"_SellStep{STEP}Body"
build_mixin = f"_SellStep{STEP}Build"
uses_fields_logic = LOGIC_FILE.exists() or f"_SellStep{STEP}Fields" in "\n".join(lines)


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


state_line = find(state_marker)
build_line = find("Widget build(BuildContext context)", state_line)
build_end = method_end(build_line)

build_block = "\n".join(lines[build_line - 1 : build_end])
lifecycle = "\n".join(lines[state_line + 1 : build_line - 1])
widget_block = "\n".join(lines[:state_line])

if uses_fields_logic:
    shell = (
        f"{widget_block}\n"
        f"class _SellStep{STEP}PageState extends _SellStep{STEP}Fields\n"
        f"    with {logic_mixin}, {build_mixin} {{\n"
        f"{lifecycle}\n"
        "}\n"
    )
    build_header = f"mixin {build_mixin} on {logic_mixin} {{\n"
else:
    shell = (
        f"{widget_block}\n"
        f"mixin {body_mixin} on State<SellStep{STEP}Page> {{\n"
        f"{lifecycle}\n"
        "}\n\n"
        f"class _SellStep{STEP}PageState extends State<SellStep{STEP}Page>\n"
        f"    with {body_mixin}, {build_mixin} {{}}\n"
    )
    build_header = f"mixin {build_mixin} on {body_mixin} {{\n"

BUILD_FILE.write_text(
    "part of 'sell_flow.dart';\n\n"
    f"{build_header}"
    f"{build_block}\n"
    "}\n",
    encoding="utf-8",
)
STEP_FILE.write_text(shell, encoding="utf-8")

part_name = f"sell_step{STEP}_build.dart"
flow = FLOW.read_text(encoding="utf-8")
if f"part '{part_name}'" not in flow:
    flow = flow.replace(
        f"part 'sell_step{STEP}.dart';",
        f"part '{part_name}';\npart 'sell_step{STEP}.dart';",
    )
    FLOW.write_text(flow, encoding="utf-8")

print("step", STEP, "build", len(build_block.splitlines()), "shell", len(shell.splitlines()))
