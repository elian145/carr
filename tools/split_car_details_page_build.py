"""Split car_details_page_build.dart into shell, hero sliver, and body sliver mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/pages/car_details_page_build.dart"
DETAILS = REPO / "lib/pages/car_details_page.dart"
OUT = REPO / "lib/pages"

lines = FILE.read_text(encoding="utf-8").splitlines()

build_start = next(i for i, line in enumerate(lines) if "Widget build(BuildContext context)" in line)
if build_start > 0 and lines[build_start - 1].strip() == "@override":
    build_start -= 1

slivers_line = next(i for i, line in enumerate(lines) if line.strip() == "slivers: [")
hero_start = next(i for i, line in enumerate(lines) if line.strip() == "SliverAppBar(")
body_start = next(i for i, line in enumerate(lines) if line.strip() == "SliverToBoxAdapter(")
body_close_line = next(
    i
    for i in range(body_start + 1, len(lines))
    if lines[i].rstrip() == "                )," and lines[i + 1].strip() == "],"
)
specs_start = next(
    i for i, line in enumerate(lines) if line.strip().startswith("Widget _buildSpecsGrid()")
)

hero_block = "\n".join(lines[hero_start:body_start]).rstrip().rstrip(",")
body_block = "\n".join(lines[body_start : body_close_line + 1]).rstrip().rstrip(",")
specs_block = lines[specs_start].rstrip()

shell_block = "\n".join(
    lines[build_start:slivers_line + 1]
    + [
        "                _buildCarDetailsHeroSliver(context, isLightShell),",
        "                _buildCarDetailsBodySliver(context, isLightShell),",
    ]
    + lines[body_close_line + 1 : specs_start]
).rstrip()

(OUT / "car_details_page_build_hero.dart").write_text(
    "part of 'car_details_page.dart';\n\n"
    "mixin _CarDetailsPageBuildHero on _CarDetailsPageContact {\n"
    "  Widget _buildCarDetailsHeroSliver(BuildContext context, bool isLightShell) {\n"
    f"    return {hero_block};\n"
    "  }\n"
    "}\n",
    encoding="utf-8",
)

(OUT / "car_details_page_build_body.dart").write_text(
    "part of 'car_details_page.dart';\n\n"
    "mixin _CarDetailsPageBuildBody on _CarDetailsPageBuildHero {\n"
    "  Widget _buildCarDetailsBodySliver(BuildContext context, bool isLightShell) {\n"
    f"    return {body_block};\n"
    "  }\n\n"
    f"{specs_block}\n"
    "}\n",
    encoding="utf-8",
)

(FILE).write_text(
    "part of 'car_details_page.dart';\n\n"
    "mixin _CarDetailsPageBuild on _CarDetailsPageBuildBody {\n"
    f"{shell_block}\n"
    "}\n",
    encoding="utf-8",
)

details = DETAILS.read_text(encoding="utf-8")
for part_name in ("car_details_page_build_hero.dart", "car_details_page_build_body.dart"):
    part = f"part '{part_name}';\n"
    if part not in details:
        details = details.replace(
            "part 'car_details_page_build.dart';\n",
            part + "part 'car_details_page_build.dart';\n",
        )

if "_CarDetailsPageBuildHero" not in details:
    details = details.replace(
        "        _CarDetailsPageBuild {}",
        "        _CarDetailsPageBuildHero,\n"
        "        _CarDetailsPageBuildBody,\n"
        "        _CarDetailsPageBuild {}",
    )

DETAILS.write_text(details, encoding="utf-8")
print("Split car_details_page_build")
