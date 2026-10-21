/// Canonical fuel / powertrain vocabulary shared by Sell, Search, the listing
/// payload and the spec catalog.
///
/// Stored listing values (`fuel_type` / `engine_type`) and Search filter values
/// are exactly one of [kFuelKeys]: `gasoline`, `diesel`, `electric`, `hybrid`,
/// `plug-in hybrid`. Display labels live in `sellFlowFuelLabel`; translations in
/// `translateListingValue` (never in this file).
///
/// The bundled spec dataset only has THREE source fuel values (Petrol / Diesel /
/// Electric) and says nothing about hybrids in that field: hybrid evidence is in
/// the variant NAME ("Corolla 1 8 (122 Hp) Hybrid e-CVT", "Prius ... Plug-in
/// Hybrid", "Panamera ... E-Hybrid") and in the dataset's habit of labelling
/// plug-in hybrids / range extenders "Electric" while they also state a
/// combustion displacement. [classifyCatalogFuelKey] turns that evidence into the
/// canonical key, once, for every consumer of the catalog.
library;

const String kFuelGasoline = 'gasoline';
const String kFuelDiesel = 'diesel';
const String kFuelElectric = 'electric';
const String kFuelHybrid = 'hybrid';
const String kFuelPlugInHybrid = 'plug-in hybrid';

/// Every canonical fuel key, in display order.
const List<String> kFuelKeys = <String>[
  kFuelGasoline,
  kFuelDiesel,
  kFuelElectric,
  kFuelHybrid,
  kFuelPlugInHybrid,
];

String _fold(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[\s_\-/+]+'), ' ').trim();

/// The canonical fuel key of any spelling the app, the API or legacy rows use
/// (`Hybrid`, `HYBRID`, `Plug-in Hybrid`, `plug_in_hybrid`, `plugin hybrid`,
/// `PHEV`, `Petrol`, ...), or null when [raw] is not a recognised fuel.
///
/// Deliberately exact on the folded text: `mild hybrid`, `lpg`, `hydrogen` ...
/// are NOT folded into `hybrid` / `gasoline`.
String? canonicalFuelKey(String? raw) {
  if (raw == null) return null;
  switch (_fold(raw)) {
    case 'gasoline':
    case 'gasoline fuel':
    case 'gas':
    case 'petrol':
    case 'petrol gasoline':
    case 'benzin':
      return kFuelGasoline;
    case 'diesel':
      return kFuelDiesel;
    case 'electric':
    case 'ev':
    case 'bev':
    case 'battery electric':
      return kFuelElectric;
    case 'hybrid':
    case 'hev':
    case 'full hybrid':
    case 'self charging hybrid':
      return kFuelHybrid;
    case 'plug in hybrid':
    case 'plugin hybrid':
    case 'plug in':
    case 'plugin':
    case 'phev':
    case 'erev':
    case 'range extender':
      return kFuelPlugInHybrid;
  }
  return null;
}

/// Value to store / send for a Sell or Search fuel selection: the canonical key
/// when the spelling is recognised, otherwise the trimmed lower-case text
/// (unchanged legacy behaviour for any other value).
String fuelStorageValue(String? raw) {
  final k = canonicalFuelKey(raw);
  if (k != null) return k;
  return (raw ?? '').trim().toLowerCase();
}

// ---------------------------------------------------------------------------
// Catalog classification
// ---------------------------------------------------------------------------

String _nameKey(String? label) =>
    ' ${(label ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim()} ';

/// Explicit plug-in / range-extender wording in a catalog variant name.
/// `e-hybrid` / `ehybrid` (Audi, VW, Porsche) are plug-in systems by name.
/// "Extended range" is deliberately NOT wording: on a battery car it only names
/// the long-range battery ("Micra Electric Extended Range"); a real extended-
/// range vehicle is caught by the combustion-displacement rule instead.
final RegExp _plugInWording = RegExp(
  r' (plug in|phev|e hybrid|ehybrid|erev|reev|range extender) ',
);

/// "Mild hybrid" / MHEV / 48 V / "Hybrid Assist": a combustion car with a small
/// assist motor. It is NOT a hybrid for Sell / Search (it keeps its Petrol /
/// Diesel fuel).
final RegExp _mildWording = RegExp(r' (mild hybrid|mhev|48v|hybrid assist) ');

/// Full-hybrid wording: the word Hybrid (also `Hybrid4`), HEV / FHEV, Toyota HSD
/// (Hybrid Synergy Drive) and Nissan e-POWER.
final RegExp _hybridWording = RegExp(r' (hybrid\d*|hev|fhev|hsd|e power) ');

/// The canonical fuel key of a catalog row.
///
/// * [datasetFuel] is the source's own value (`Petrol (Gasoline)`, `Diesel`,
///   `Electric`).
/// * [label] is the variant name (`"<model> <trim>"`), the only place the source
///   states hybrid wording.
/// * [hasCombustionEngine] is true when the row states a combustion
///   displacement.
///
/// Rules (evidence only, nothing is invented):
///  1. Plug-in / range-extender wording -> `plug-in hybrid` (any source fuel).
///  2. A source "Electric" row that also states a combustion displacement is not
///     a pure electric car; it is a plug-in hybrid / range extender.
///  3. Full-hybrid wording (after removing "mild hybrid") -> `hybrid`.
///  4. Otherwise the source fuel: diesel -> `diesel`, electric -> `electric`,
///     anything else -> `gasoline`. Mild hybrids therefore stay Petrol / Diesel.
String classifyCatalogFuelKey({
  required String? datasetFuel,
  String? label,
  bool hasCombustionEngine = false,
}) {
  final ft = (datasetFuel ?? '').toLowerCase();
  final String base;
  if (ft.contains('diesel')) {
    base = kFuelDiesel;
  } else if (ft.contains('electric') && !ft.contains('hybrid')) {
    base = kFuelElectric;
  } else if (ft.contains('plug') && ft.contains('hybrid')) {
    base = kFuelPlugInHybrid;
  } else if (ft.contains('hybrid')) {
    base = kFuelHybrid;
  } else {
    base = kFuelGasoline;
  }
  if (base == kFuelPlugInHybrid) return base;

  final name = _nameKey(label);
  if (_plugInWording.hasMatch(name)) return kFuelPlugInHybrid;
  if (base == kFuelElectric && hasCombustionEngine) return kFuelPlugInHybrid;
  if (base == kFuelHybrid) return base;

  final withoutMild = name.replaceAll(_mildWording, ' ');
  if (_hybridWording.hasMatch(withoutMild)) return kFuelHybrid;
  return base;
}
