"""Extract sell step 4 preview widgets into a separate part file."""
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
step4 = REPO / "lib/features/sell/sell_step4.dart"
flow = REPO / "lib/features/sell/sell_flow.dart"
lines = step4.read_text(encoding="utf-8").splitlines()

preview_start = next(
    i for i, line in enumerate(lines) if line.startswith("class _PreviewMediaEntry")
)

preview_body = "\n".join(lines[preview_start:])
(step4.parent / "sell_step4_preview.dart").write_text(
    f"part of 'sell_flow.dart';\n\n{preview_body}\n",
    encoding="utf-8",
)

step4.write_text("\n".join(lines[:preview_start]).rstrip() + "\n", encoding="utf-8")

flow_text = flow.read_text(encoding="utf-8")
if "part 'sell_step4_preview.dart';" not in flow_text:
    flow_text = flow_text.replace(
        "part 'sell_step4.dart';",
        "part 'sell_step4.dart';\npart 'sell_step4_preview.dart';",
    )
    flow.write_text(flow_text, encoding="utf-8")

print(f"sell_step4.dart: {preview_start} lines")
print(f"sell_step4_preview.dart: {len(lines) - preview_start} lines")
