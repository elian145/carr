from pathlib import Path
import re

text = Path("lib/features/home/home_page.dart").read_text(encoding="utf-8")
m = re.search(r"final List<String> engineSizes = \[(.*?)\];", text, re.S)
items = re.findall(r"'([^']*)'", m.group(1))
lines = [
    "/// Engine size filter/sell options (0.5L–16.0L step 0.1).",
    "const List<String> kEngineSizeFilterOptions = [",
]
for it in items:
    lines.append(f"  '{it}',")
lines.append("];")
lines.append("")
Path("lib/shared/listings/engine_size_filter_options.dart").write_text(
    "\n".join(lines),
    encoding="utf-8",
)
print(len(items), "entries")
