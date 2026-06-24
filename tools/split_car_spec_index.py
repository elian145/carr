"""Split car_spec_index.dart into focused part files (parse, impl, types, labels, models)."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/services/car_spec_index.dart"
OUT = REPO / "lib/services"

lines = FILE.read_text(encoding="utf-8").splitlines()

first_decl = next(
    i
    for i, line in enumerate(lines)
    if line.strip() and not line.startswith("import ") and not line.startswith("//")
)
load_result_start = next(i for i, line in enumerate(lines) if line.startswith("class CarSpecIndexLoadResult"))
index_start = next(
    i
    for i, line in enumerate(lines)
    if line.startswith("class CarSpecIndex ") or line.startswith("class CarSpecIndex {")
)
types_start = next(i for i, line in enumerate(lines) if line.startswith("class CarDatasetVariant"))
labels_start = next(i for i, line in enumerate(lines) if line.startswith("String sellFlowTransmissionLabel"))
models_start = next(i for i, line in enumerate(lines) if line.startswith("class _Brand"))

imports = "\n".join(lines[:first_decl]).rstrip()
parse_block = "\n".join(lines[first_decl:index_start]).rstrip()
impl_block = "\n".join(lines[index_start:types_start]).rstrip()
types_block = "\n".join(lines[types_start:labels_start]).rstrip()
labels_block = "\n".join(lines[labels_start:models_start]).rstrip()
models_block = "\n".join(lines[models_start:]).rstrip()

(FILE).write_text(
    imports
    + "\n\n"
    + "part 'car_spec_index_parse.dart';\n"
    + "part 'car_spec_index_base.dart';\n"
    + "part 'car_spec_index_helpers.dart';\n"
    + "part 'car_spec_index_catalog.dart';\n"
    + "part 'car_spec_index_home.dart';\n"
    + "part 'car_spec_index_impl.dart';\n"
    + "part 'car_spec_index_types.dart';\n"
    + "part 'car_spec_index_sell_labels.dart';\n"
    + "part 'car_spec_index_models.dart';\n",
    encoding="utf-8",
)

(OUT / "car_spec_index_parse.dart").write_text(
    "part of 'car_spec_index.dart';\n\n" + parse_block + "\n",
    encoding="utf-8",
)

(OUT / "car_spec_index_impl.dart").write_text(
    "part of 'car_spec_index.dart';\n\n" + impl_block + "\n",
    encoding="utf-8",
)

(OUT / "car_spec_index_types.dart").write_text(
    "part of 'car_spec_index.dart';\n\n" + types_block + "\n",
    encoding="utf-8",
)

(OUT / "car_spec_index_sell_labels.dart").write_text(
    "part of 'car_spec_index.dart';\n\n" + labels_block + "\n",
    encoding="utf-8",
)

(OUT / "car_spec_index_models.dart").write_text(
    "part of 'car_spec_index.dart';\n\n" + models_block + "\n",
    encoding="utf-8",
)

print("Split car_spec_index")
print("Run tools/split_car_spec_index_impl.py after editing the monolithic impl export.")
