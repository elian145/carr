part of 'car_spec_index.dart';

/// Evidence-only normalization of the spec dataset's body type and drivetrain.
///
/// Contract (shared by Search, Sell and the catalog apply):
///   * a value is produced ONLY from an explicit, recognised source token;
///   * unknown / blank / unsupported source text produces NOTHING (an empty set /
///     null) - it never turns into Sedan, FWD or any other factual spec;
///   * no "closest category" is ever invented.
///
/// All values here are the app's API-style keys; [sellFlowBodyLabel] /
/// [sellFlowDriveLabel] turn them into the Sell/Search display labels.

/// Dataset body token (lower-cased, hyphens and runs of spaces folded to one
/// space) -> app body key. Every entry is an exact token, never a substring, so
/// `minivan` can never be read as `van`.
const Map<String, String> _kBodyTokenToKey = <String, String>{
  // Sedan
  'sedan': 'sedan',
  'saloon': 'sedan',
  // SUV
  'suv': 'suv',
  'off road vehicle': 'suv',
  'sport utility': 'suv',
  'crossover': 'suv',
  'cuv': 'suv',
  'sav': 'suv',
  'sac': 'suv',
  // Hatchback
  'hatchback': 'hatchback',
  'liftback': 'hatchback',
  // Coupe
  'coupe': 'coupe',
  // Pickup
  'pick up': 'pickup',
  'pickup': 'pickup',
  // Wagon
  'station wagon (estate)': 'wagon',
  'station wagon': 'wagon',
  'wagon': 'wagon',
  'estate': 'wagon',
  'variant': 'wagon',
  // Convertible
  'cabriolet': 'convertible',
  'roadster': 'convertible',
  'targa': 'convertible',
  'convertible': 'convertible',
  // Minivan
  'minivan': 'minivan',
  'mpv': 'minivan',
  // Van (explicit only)
  'van': 'van',
};

/// Splits a combined dataset body value (`"Station wagon (estate), Crossover"`,
/// `"Coupe - Cabriolet"`) into its tokens. Only `,` and a *spaced* dash separate
/// tokens, so `Pick-up` / `Off-road vehicle` stay intact.
List<String> _bodyTokens(String? raw) {
  if (raw == null) return const <String>[];
  final out = <String>[];
  for (final part in raw.split(RegExp(r'\s*,\s*|\s+-\s+'))) {
    final t = part
        .toLowerCase()
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (t.isNotEmpty) out.add(t);
  }
  return out;
}

/// Every body category explicitly recognised in one raw dataset body value.
///
/// A combined value yields every recognised category (`Station wagon (estate),
/// Crossover` -> `{wagon, suv}`); unrecognised tokens (Fastback, Grand Tourer,
/// Quadricycle, anything unknown) contribute nothing. Blank/unknown -> empty set.
Set<String> carSpecBodyKeys(String? raw) {
  final out = <String>{};
  for (final t in _bodyTokens(raw)) {
    final k = _kBodyTokenToKey[t];
    if (k != null) out.add(k);
  }
  return out;
}

/// The single body key of a row, or null when the row has none or several.
/// Used only for form serialization (pre-filling one field); with a combined
/// value nothing is pre-selected rather than picking one arbitrarily.
String? carSpecSingleBodyKey(Set<String> keys) =>
    keys.length == 1 ? keys.first : null;

/// One drivetrain field (`drivetrain` or `Traction:`) -> `fwd` / `rwd` / `awd`,
/// or null when it is blank, unknown, or names more than one layout.
String? _driveKeyFromText(String? raw) {
  final t = (raw ?? '').toLowerCase().replaceAll('-', ' ').trim();
  if (t.isEmpty) return null;
  final found = <String>{};
  if (RegExp(r'\bawd\b').hasMatch(t) ||
      t.contains('all wheel') ||
      t.contains('4x4') ||
      RegExp(r'\b4 ?wd\b').hasMatch(t) ||
      t.contains('four wheel')) {
    found.add('awd');
  }
  if (RegExp(r'\brwd\b').hasMatch(t) || t.contains('rear wheel')) {
    found.add('rwd');
  }
  if (RegExp(r'\bfwd\b').hasMatch(t) || t.contains('front wheel')) {
    found.add('fwd');
  }
  return found.length == 1 ? found.first : null;
}

/// Drivetrain of one dataset row from its two evidence fields.
///
///  A. both recognised and equal      -> that value
///  B. only one recognised            -> that value
///  C. both recognised but different  -> null (the source contradicts itself)
///  D. neither recognised             -> null
String? carSpecDriveKey(String? drivetrain, String? traction) {
  final a = _driveKeyFromText(drivetrain);
  final b = _driveKeyFromText(traction);
  if (a != null && b != null) return a == b ? a : null;
  return a ?? b;
}
