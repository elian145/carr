"""Split lib/pages/sell_page.dart into extension part files."""
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
src_path = REPO / "lib/pages/sell_page.dart"
lines = src_path.read_text(encoding="utf-8").splitlines()

sections = [
    ("sell_page_draft.dart", "SellPageDraft", 180, 784),
    ("sell_page_catalog.dart", "SellPageCatalog", 784, 1011),
    ("sell_page_media.dart", "SellPageMedia", 1011, 1165),
    ("sell_page_submit.dart", "SellPageSubmit", 1165, 1366),
    ("sell_page_catalog_ui.dart", "SellPageCatalogUi", 1366, 1626),
    ("sell_page_fields.dart", "SellPageFields", 1626, 2152),
]

label_maps = "\n".join(lines[1626:1650]).replace("  static const ", "const ")

out_dir = REPO / "lib/pages/sell"
out_dir.mkdir(exist_ok=True)

part_lines = []
for fname, ext_name, start, end in sections:
    body = "\n".join(lines[start:end])
    prefix = ""
    if fname == "sell_page_fields.dart":
        prefix = label_maps + "\n\n"
    part_text = (
        f"part of '../sell_page.dart';\n\n"
        f"// ignore_for_file: invalid_use_of_protected_member, library_private_types_in_public_api\n\n"
        f"{prefix}"
        f"extension {ext_name} on _SellPageState {{\n"
        f"{body}\n"
        f"}}\n"
    )
    (out_dir / fname).write_text(part_text, encoding="utf-8")
    part_lines.append(f"part 'sell/{fname}';")

class_body = "\n".join(lines[37:179])
build_body = "\n".join(lines[2153:2774])

header = "\n".join(lines[0:20]) + "\n"
sell_page_widget = "\n".join(lines[20:35])
parts_block = "\n".join(part_lines)

main = f"""{header}
{parts_block}

{sell_page_widget}

class _SellPageState extends State<SellPage> {{
{class_body}
{build_body}
}}
"""

src_path.write_text(main, encoding="utf-8")
print(f"main: {len(main.splitlines())} lines")
