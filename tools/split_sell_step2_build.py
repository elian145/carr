"""Split sell_step2_build.dart into section mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
BUILD = REPO / "lib/features/sell/sell_step2_build.dart"
FLOW = REPO / "lib/features/sell/sell_flow.dart"
OUT = REPO / "lib/features/sell"

lines = BUILD.read_text(encoding="utf-8").splitlines()

SECTIONS = [
    (
        "sell_step2_build_core.dart",
        "_SellStep2BuildCore",
        "_SellStep2Pickers",
        "// Header",
        "// Body Type",
        "_sellStep2BuildCoreSection",
    ),
    (
        "sell_step2_build_appearance.dart",
        "_SellStep2BuildAppearance",
        "_SellStep2BuildCore",
        "// Body Type",
        "// Drive Type",
        "_sellStep2BuildAppearanceSection",
    ),
    (
        "sell_step2_build_mechanical.dart",
        "_SellStep2BuildMechanical",
        "_SellStep2BuildAppearance",
        "// Drive Type",
        "SizedBox(height: 32)",
        "_sellStep2BuildMechanicalSection",
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


nav_start = find("SizedBox(height: 32)", find("// VIN"))
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

(OUT / "sell_step2_build.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    "mixin _SellStep2Build on _SellStep2BuildMechanical {\n"
    "  List<Widget> _sellStep2BuildNavSection() {\n"
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
    "            ..._sellStep2BuildCoreSection(),\n"
    "            ..._sellStep2BuildAppearanceSection(),\n"
    "            ..._sellStep2BuildMechanicalSection(),\n"
    "            ..._sellStep2BuildNavSection(),\n"
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
            "part 'sell_step2_build.dart';",
            f"part '{filename}';\npart 'sell_step2_build.dart';",
        )
FLOW.write_text(flow, encoding="utf-8")

step2 = REPO / "lib/features/sell/sell_step2.dart"
step2_text = step2.read_text(encoding="utf-8")
step2_text = step2_text.replace(
    "with _SellStep2Catalog, _SellStep2Pickers, _SellStep2Build",
    "with _SellStep2Catalog, _SellStep2Pickers, _SellStep2BuildCore, "
    "_SellStep2BuildAppearance, _SellStep2BuildMechanical, _SellStep2Build",
)
step2.write_text(step2_text, encoding="utf-8")

print("ok")
