"""Split sell_step4_build.dart into media section mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
BUILD = REPO / "lib/features/sell/sell_step4_build.dart"
FLOW = REPO / "lib/features/sell/sell_flow.dart"
STEP4 = REPO / "lib/features/sell/sell_step4.dart"
OUT = REPO / "lib/features/sell"

lines = BUILD.read_text(encoding="utf-8").splitlines()

SECTIONS = [
    (
        "sell_step4_build_intro.dart",
        "_SellStep4BuildIntro",
        "_SellStep4Logic",
        "// Header",
        "// Photos Section",
        "_sellStep4BuildIntroSection",
    ),
    (
        "sell_step4_build_photos.dart",
        "_SellStep4BuildPhotos",
        "_SellStep4BuildIntro",
        "// Photos Section",
        "// Damage / crash photos",
        "_sellStep4BuildPhotosSection",
    ),
    (
        "sell_step4_build_damage.dart",
        "_SellStep4BuildDamage",
        "_SellStep4BuildPhotos",
        "// Damage / crash photos",
        "// Videos Section",
        "_sellStep4BuildDamageSection",
    ),
    (
        "sell_step4_build_videos.dart",
        "_SellStep4BuildVideos",
        "_SellStep4BuildDamage",
        "// Videos Section",
        "SizedBox(height: 32)",
        "_sellStep4BuildVideosSection",
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


nav_start = find("// Navigation Buttons")
nav_end = find("          ),", nav_start)
nav_block = "\n".join(lines[nav_start : nav_end + 1]).rstrip()

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

(OUT / "sell_step4_build.dart").write_text(
    "part of 'sell_flow.dart';\n\n"
    "mixin _SellStep4Build on _SellStep4BuildVideos {\n"
    "  List<Widget> _sellStep4BuildNavSection() {\n"
    "    return [\n"
    f"{nav_block}\n"
    "    ];\n"
    "  }\n\n"
    "  @override\n"
    "  Widget build(BuildContext context) {\n"
    "    return SingleChildScrollView(\n"
    "      padding: EdgeInsets.all(20),\n"
    "      child: Column(\n"
    "        crossAxisAlignment: CrossAxisAlignment.start,\n"
    "        children: [\n"
    "          ..._sellStep4BuildIntroSection(),\n"
    "          ..._sellStep4BuildPhotosSection(),\n"
    "          ..._sellStep4BuildDamageSection(),\n"
    "          ..._sellStep4BuildVideosSection(),\n"
    "          ..._sellStep4BuildNavSection(),\n"
    "        ],\n"
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
            "part 'sell_step4_build.dart';",
            f"part '{filename}';\npart 'sell_step4_build.dart';",
        )
FLOW.write_text(flow, encoding="utf-8")

step4 = STEP4.read_text(encoding="utf-8")
step4 = step4.replace(
    "_SellStep4Fields, _SellStep4Logic, _SellStep4Build",
    "_SellStep4Fields, _SellStep4Logic, _SellStep4BuildIntro, "
    "_SellStep4BuildPhotos, _SellStep4BuildDamage, _SellStep4BuildVideos, "
    "_SellStep4Build",
)
STEP4.write_text(step4, encoding="utf-8")

print("ok")
