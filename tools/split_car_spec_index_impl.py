"""Split car_spec_index_impl.dart into base, helpers, catalog, and home-filter mixins."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
IMPL = REPO / "lib/services/car_spec_index_impl.dart"
SHELL = REPO / "lib/services/car_spec_index.dart"
OUT = REPO / "lib/services"

lines = IMPL.read_text(encoding="utf-8").splitlines()
# Drop "part of" header (first 2 lines: part of + blank)
body = lines[2:]
if body and body[0].startswith("class CarSpecIndex"):
    body = body[1:]

idx = {name: next(i for i, line in enumerate(body) if line.startswith(name)) for name in [
    "  int? datasetBrandId",
    "  List<({int datasetModelId",
    "  void _sortCatalogSellRows",
    "  List<_Model> _familyModels",
    "  static double trimMatchScore",
    "  int? suggestDatasetModelId",
    "  ({List<String> engineSizes",
    "  List<OnlineSpecVariant> homeFilterSpecVariantsUnion",
    "  static String _homeFilterVariantDedupeKey",
    "  bool _trimMatchesUserLabel",
    "  CatalogSpecFields? appliedFieldsFor",
    "  static String _catalogDisplacementBadgeContext",
]}

base_end = idx["  int? datasetBrandId"]
catalog_a = body[idx["  int? datasetBrandId"] : idx["  List<({int datasetModelId"]]
helpers_a = body[idx["  List<({int datasetModelId"] : idx["  int? suggestDatasetModelId"]]
catalog_b = body[idx["  int? suggestDatasetModelId"] : idx["  ({List<String> engineSizes"]]
home_block = (
    body[idx["  ({List<String> engineSizes"] : idx["  bool _trimMatchesUserLabel"]]
    + body[idx["  static String _homeFilterVariantDedupeKey"] : idx["  bool _trimMatchesUserLabel"]]
    + body[idx["  CatalogSpecFields? appliedFieldsFor"] : idx["  static String _catalogDisplacementBadgeContext"]]
)
helpers_b = body[idx["  bool _trimMatchesUserLabel"] : idx["  CatalogSpecFields? appliedFieldsFor"]]
helpers_c = body[idx["  static String _catalogDisplacementBadgeContext"] : -1]

base_block = body[:base_end]
base_text = "\n".join(base_block).replace("CarSpecIndex._({", "CarSpecIndexBase._({", 1)
catalog_block = catalog_a + catalog_b
helpers_block = helpers_a + helpers_b + helpers_c

shell = SHELL.read_text(encoding="utf-8")
shell = shell.replace(
    "part 'car_spec_index_impl.dart';\n",
    "part 'car_spec_index_base.dart';\n"
    "part 'car_spec_index_helpers.dart';\n"
    "part 'car_spec_index_catalog.dart';\n"
    "part 'car_spec_index_home.dart';\n"
    "part 'car_spec_index_impl.dart';\n",
)
SHELL.write_text(shell, encoding="utf-8")

(OUT / "car_spec_index_base.dart").write_text(
    "part of 'car_spec_index.dart';\n\n"
    "abstract class CarSpecIndexBase {\n"
    + base_text
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "car_spec_index_helpers.dart").write_text(
    "part of 'car_spec_index.dart';\n\n"
    "mixin CarSpecIndexHelpers on CarSpecIndexBase {\n"
    + "\n".join(helpers_block)
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "car_spec_index_catalog.dart").write_text(
    "part of 'car_spec_index.dart';\n\n"
    "mixin CarSpecIndexCatalog on CarSpecIndexHelpers {\n"
    + "\n".join(catalog_block)
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "car_spec_index_home.dart").write_text(
    "part of 'car_spec_index.dart';\n\n"
    "mixin CarSpecIndexHomeFilter on CarSpecIndexCatalog {\n"
    + "\n".join(home_block)
    + "\n}\n",
    encoding="utf-8",
)

(OUT / "car_spec_index_impl.dart").write_text(
    "part of 'car_spec_index.dart';\n\n"
    "class CarSpecIndex extends CarSpecIndexBase\n"
    "    with CarSpecIndexHelpers, CarSpecIndexCatalog, CarSpecIndexHomeFilter {\n"
    "  static const String catalogAutofillModelOnly =\n"
    "      CarSpecIndexBase.catalogAutofillModelOnly;\n"
    "  static const String assetPath = CarSpecIndexBase.assetPath;\n\n"
    "  static Future<CarSpecIndexLoadResult> loadWithResult() =>\n"
    "      CarSpecIndexBase.loadWithResult();\n\n"
    "  static Future<CarSpecIndex?> load() => CarSpecIndexBase.load();\n\n"
    "  CarSpecIndex._({\n"
    "    required Map<int, _Brand> brandsById,\n"
    "    required Map<int, _Model> modelsById,\n"
    "    required Map<int, List<_Model>> modelsByBrandId,\n"
    "    required Map<int, List<_Trim>> trimsByModelId,\n"
    "    required Map<int, _Spec> specByTrimId,\n"
    "  }) : super._(\n"
    "          brandsById: brandsById,\n"
    "          modelsById: modelsById,\n"
    "          modelsByBrandId: modelsByBrandId,\n"
    "          trimsByModelId: trimsByModelId,\n"
    "          specByTrimId: specByTrimId,\n"
    "        );\n"
    "}\n",
    encoding="utf-8",
)

print("Split car_spec_index_impl into mixins")
