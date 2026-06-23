"""Split sell_step3_build.dart into section mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
BUILD = REPO / "lib/features/sell/sell_step3_build.dart"
FLOW = REPO / "lib/features/sell/sell_flow.dart"
STEP3 = REPO / "lib/features/sell/sell_step3.dart"
OUT = REPO / "lib/features/sell"

lines = BUILD.read_text(encoding="utf-8").splitlines()

SECTIONS = [
    (
        "sell_step3_build_price.dart",
        "_SellStep3BuildPrice",
        "_SellStep3Pickers",
        "// Price (Modal or Manual Input)",
        "// City (Modal)",
        "_sellStep3BuildPriceSection",
    ),
    (
        "sell_step3_build_details.dart",
        "_SellStep3BuildDetails",
        "_SellStep3BuildPrice",
        "// City (Modal)",
        "// Navigation Buttons",
        "_sellStep3BuildDetailsSection",
    ),
]


def find(substr: str, start: int = 0) -> int:
    for i in range(start, len(lines)):
        if substr in lines[i]:
            return i
    raise ValueError(substr)


def slice_lines(start_marker: str, end_marker: str) -> str:
    start = find(start_marker)
    end = find(end_marker, start + 1)
    return "\n".join(lines[start:end]).rstrip()


header_block = slice_lines("// Header", "// Price (Modal or Manual Input)")
nav_start = find("// Navigation Buttons")
nav_block = "\n".join(lines[nav_start : find("          ],")]).rstrip()

for filename, mixin_name, on_mixin, start_m, end_m, method_name in SECTIONS:
    block = slice_lines(start_m, end_m)
    (OUT / filename).write_text(
        "part of 'sell_flow.dart';\n\n"
        f"mixin {mixin_name} on {on_mixin} {{\n"
        f"  List<Widget> {method_name}() {{\n"
        f"    return [\n"
        f"{block}\n"
        f"    ];\n"
        f"  }}\n"
        f"}}\n",
        encoding="utf-8",
    )

(OUT / "sell_step3_build.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    "mixin _SellStep3Build on _SellStep3BuildDetails {\n"
    "  List<Widget> _sellStep3BuildHeaderSection() {\n"
    "    return [\n"
    f"{header_block}\n"
    "    ];\n"
    "  }\n\n"
    "  List<Widget> _sellStep3BuildNavSection() {\n"
    "    return [\n"
    f"{nav_block}\n"
    "    ];\n"
    "  }\n\n"
    "  @override\n"
    "  Widget build(BuildContext context) {\n"
    "    return SingleChildScrollView(\n"
    "      padding: EdgeInsets.all(20),\n"
    "      child: Form(\n"
    "        key: _formKey,\n"
    "        child: Column(\n"
    "          crossAxisAlignment: CrossAxisAlignment.start,\n"
    "          children: [\n"
    "            ..._sellStep3BuildHeaderSection(),\n"
    "            ..._sellStep3BuildPriceSection(),\n"
    "            ..._sellStep3BuildDetailsSection(),\n"
    "            ..._sellStep3BuildNavSection(),\n"
    "          ],\n"
    "        ),\n"
    "      ),\n"
    "    );\n"
    "  }\n"
    "}\n",
    encoding="utf-8",
)

flow = FLOW.read_text(encoding="utf-8")
for filename, *_ in SECTIONS:
    part = f"part '{filename}';"
    if part not in flow:
        flow = flow.replace(
            "part 'sell_step3_build.dart';",
            f"part '{filename}';\npart 'sell_step3_build.dart';",
        )
FLOW.write_text(flow, encoding="utf-8")

step3 = STEP3.read_text(encoding="utf-8")
step3 = step3.replace(
    "_SellStep3Fields, _SellStep3Catalog, _SellStep3Pickers, _SellStep3Build",
    "_SellStep3Fields, _SellStep3Catalog, _SellStep3Pickers, "
    "_SellStep3BuildPrice, _SellStep3BuildDetails, _SellStep3Build",
)
STEP3.write_text(step3, encoding="utf-8")

print("ok")
