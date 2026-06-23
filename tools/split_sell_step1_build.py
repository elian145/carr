"""Extract sell_step1 build method into sell_step1_build.dart mixin."""
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


def state_line = find("class _SellStep1PageState")
build_line = find("Widget build(BuildContext context)", state_line)
build_end = method_end(build_line)

build_block = "\n".join(lines[build_line - 1 : build_end])
lifecycle = "\n".join(lines[state_line + 1 : build_line - 1])
shell = (
    "\n".join(lines[: state_line])
    + "\nclass _SellStep1PageState extends _SellStep1Fields\n"
    + "    with _SellStep1Logic, _SellStep1Build {\n"
    + lifecycle
    + "\n}\n"
)

(REPO / "lib/features/sell/sell_step1_build.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    "mixin _SellStep1Build on _SellStep1Logic {\n"
    f"{build_block}\n"
    "}\n",
    encoding="utf-8",
)
STEP1.write_text(shell, encoding="utf-8")

flow = FLOW.read_text(encoding="utf-8")
if "sell_step1_build.dart" not in flow:
    flow = flow.replace(
        "part 'sell_step1.dart';",
        "part 'sell_step1_build.dart';\npart 'sell_step1.dart';",
    )
    FLOW.write_text(flow, encoding="utf-8")

print("build lines", build_end - build_line + 1, "shell lines", len(shell.splitlines()))
