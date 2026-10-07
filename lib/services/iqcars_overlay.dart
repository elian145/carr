import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../shared/debug/app_log.dart';

/// Approved, additive IQ Cars additions for ONE brand + model.
///
/// The three lists are independent model-level lists. They carry no
/// trim -> engine -> cylinder relationship and never describe removals.
@immutable
class IqCarsModelAdditions {
  const IqCarsModelAdditions({
    this.trims = const <String>[],
    this.engineVariants = const <IqEngineVariant>[],
    this.cylinders = const <int>[],
  });

  /// Genuinely new trim names, in the exported (deterministic) order.
  final List<String> trims;

  /// Approved engine variants (displacement + source qualifier), ascending by
  /// displacement then qualifier. `2.4T` and `2.4` are different variants.
  final List<IqEngineVariant> engineVariants;

  /// The distinct displacements of [engineVariants], ascending litres.
  List<double> get engineLiters => <double>[
        for (final t in {for (final v in engineVariants) v.tenths}) t / 10,
      ];

  /// Explicitly supplied cylinder counts, ascending.
  final List<int> cylinders;

  bool get isEmpty =>
      trims.isEmpty && engineVariants.isEmpty && cylinders.isEmpty;
}

/// One approved IQ engine variant: displacement in tenths of a litre plus the
/// normalized source qualifier (`''`, `T`, `TD`, `D`, `TC`). The qualifier is
/// kept as published: nothing (fuel type, cylinders) is inferred from it.
@immutable
class IqEngineVariant {
  const IqEngineVariant(this.tenths, this.qualifier);

  final int tenths;
  final String qualifier;

  double get liters => tenths / 10;

  /// App engine-label style: `2.4`, `2.4 T`, `4.5 TD`.
  String get label =>
      '${liters.toStringAsFixed(1)}${qualifier.isEmpty ? '' : ' $qualifier'}';

  /// Identity used for deduplication (displacement + qualifier).
  String get identity => '$tenths|$qualifier';

  @override
  bool operator ==(Object other) =>
      other is IqEngineVariant && other.identity == identity;

  @override
  int get hashCode => identity.hashCode;

  @override
  String toString() => label;
}

/// Normalizes an engine qualifier for comparison: letters only, upper-case, and
/// the spelled-out forms folded onto the short ones the catalog uses
/// (`Turbo` -> `T`, `Diesel` -> `D`, `Turbo Diesel` -> `TD`). Anything else is
/// kept verbatim, so genuinely different qualifiers never collapse.
String normalizeEngineQualifier(String raw) {
  final q = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
  switch (q) {
    case 'TURBO':
      return 'T';
    case 'DIESEL':
      return 'D';
    case 'TURBODIESEL':
      return 'TD';
    default:
      return q;
  }
}

/// Splits an engine label (`2.4 D`, `2.4T`, `2.0L`, `3.5 Turbo`) into
/// displacement tenths + normalized qualifier, or null when it has no leading
/// displacement.
({int tenths, String qualifier})? parseEngineIdentity(String label) {
  final m = RegExp(
    r'^\s*(\d+(?:\.\d+)?)\s*(?:L(?:ITRES?|ITERS?)?(?![A-Za-z]))?\s*(.*)$',
    caseSensitive: false,
  ).firstMatch(label);
  if (m == null) return null;
  final liters = double.tryParse(m.group(1)!);
  if (liters == null) return null;
  return (
    tenths: (liters * 10).round(),
    qualifier: normalizeEngineQualifier(m.group(2) ?? ''),
  );
}

/// Parses the runtime asset text into plain, isolate-sendable maps
/// (`brand -> model -> {trims, engines, cylinders}`). Top-level for [compute].
///
/// Tolerant by design: anything malformed is skipped, and a document that is
/// not a JSON object yields an empty result. It never throws.
Map<String, Map<String, Map<String, List<Object>>>> parseIqCarsOverlayText(
  String raw,
) {
  final out = <String, Map<String, Map<String, List<Object>>>>{};
  try {
    final decoded = json.decode(raw);
    if (decoded is! Map) return out;
    for (final brandEntry in decoded.entries) {
      final brand = brandEntry.key.toString();
      if (brand.startsWith('_')) continue; // `_meta`
      final models = brandEntry.value;
      if (models is! Map) continue;
      final parsedModels = <String, Map<String, List<Object>>>{};
      for (final modelEntry in models.entries) {
        final adds = modelEntry.value;
        if (adds is! Map) continue;
        final trims = <Object>[];
        final seenTrims = <String>{};
        final rawTrims = adds['trims_add'];
        if (rawTrims is List) {
          for (final t in rawTrims) {
            if (t is! String) continue;
            final name = t.trim().replaceAll(RegExp(r'\s+'), ' ');
            if (name.isNotEmpty && seenTrims.add(name.toLowerCase())) {
              trims.add(name);
            }
          }
        }
        // Engines travel as "<tenths>|<qualifier>" strings (isolate-safe).
        final engines = <Object>[];
        final seenEngines = <String>{};
        void addEngine(double? liters, String qualifier) {
          if (liters == null || liters <= 0.001) return;
          final token = '${(liters * 10).round()}|$qualifier';
          if (seenEngines.add(token)) engines.add(token);
        }

        // Format 2: "<litres><qualifier>" variants, e.g. "2.4T", "4.5TD", "2.4".
        final rawVariants = adds['engine_variants_add'];
        if (rawVariants is List) {
          for (final e in rawVariants) {
            final m = e is String
                ? RegExp(r'^(\d{1,2}\.\d)\s*([A-Za-z]{1,3})?$')
                    .firstMatch(e.trim())
                : null;
            if (m == null) continue;
            addEngine(
              double.tryParse(m.group(1)!),
              normalizeEngineQualifier(m.group(2) ?? ''),
            );
          }
        }
        // Format 1 (legacy): displacement only ("2.7L"), no qualifier.
        final rawEngines = adds['engine_sizes_add'];
        if (rawEngines is List) {
          for (final e in rawEngines) {
            final m = e is String
                ? RegExp(r'^(\d{1,2}(?:\.\d)?)\s*[Ll]$').firstMatch(e.trim())
                : null;
            addEngine(m == null ? null : double.tryParse(m.group(1)!), '');
          }
        }
        final cyls = <Object>[];
        // Format 3: `cylinders` is the FULL approved IQ set (the app unions it
        // with its own CarNet baseline, empty or populated). `cylinders_add`
        // is the legacy (format <= 2) name and is read the same way.
        for (final key in const ['cylinders', 'cylinders_add']) {
          final rawCyls = adds[key];
          if (rawCyls is! List) continue;
          for (final c in rawCyls) {
            final n = c is int ? c : (c is String ? int.tryParse(c.trim()) : null);
            if (n != null && n > 0 && !cyls.contains(n)) cyls.add(n);
          }
        }
        if (trims.isEmpty && engines.isEmpty && cyls.isEmpty) continue;
        parsedModels[modelEntry.key.toString()] = <String, List<Object>>{
          'trims': trims,
          'engines': engines,
          'cylinders': cyls,
        };
      }
      if (parsedModels.isNotEmpty) out[brand] = parsedModels;
    }
  } catch (_) {
    return <String, Map<String, Map<String, List<Object>>>>{};
  }
  return out;
}

/// Compact runtime overlay of approved IQ Cars additions
/// (`assets/car_iqcars_overlay.json`, built by
/// `tools/catalog_enrichment/iqcars/export_runtime_overlay.py`).
///
/// * Loaded once, parsed once, then answered by keyed Brand + Model lookup.
/// * Additive only: every merge helper returns the baseline values untouched
///   (same order) plus genuinely new values.
/// * Fails safe: a missing / malformed asset behaves exactly like [empty].
class IqCarsOverlay {
  IqCarsOverlay._(this._byBrand, this._lowerBrand, this.modelCount);

  /// No additions: the app behaves exactly as it did before the overlay.
  static final IqCarsOverlay empty = IqCarsOverlay._(
    const <String, Map<String, IqCarsModelAdditions>>{},
    const <String, String>{},
    0,
  );

  static const String assetPath = 'assets/car_iqcars_overlay.json';

  /// Builds an overlay from the plain maps produced by [parseIqCarsOverlayText].
  ///
  /// [parsed] is deliberately an untyped [Map]: values that crossed an isolate
  /// boundary may have lost their generic type arguments.
  factory IqCarsOverlay.fromParsed(Map<dynamic, dynamic> parsed) {
    final byBrand = <String, Map<String, IqCarsModelAdditions>>{};
    final lowerBrand = <String, String>{};
    var count = 0;
    for (final b in parsed.entries) {
      final brandName = b.key.toString();
      final models = <String, IqCarsModelAdditions>{};
      for (final m in (b.value as Map<dynamic, dynamic>).entries) {
        final v = m.value as Map<dynamic, dynamic>;
        final trims =
            (v['trims'] as List<dynamic>).whereType<String>().toList();
        final engines = <IqEngineVariant>[
          for (final token in (v['engines'] as List<dynamic>).whereType<String>())
            IqEngineVariant(
              int.parse(token.split('|').first),
              token.split('|').last,
            ),
        ]..sort((a, b) => a.tenths != b.tenths
            ? a.tenths.compareTo(b.tenths)
            : a.qualifier.compareTo(b.qualifier));
        final cyls =
            (v['cylinders'] as List<dynamic>).whereType<int>().toList()
              ..sort();
        models[m.key.toString()] = IqCarsModelAdditions(
          trims: List<String>.unmodifiable(trims),
          engineVariants: List<IqEngineVariant>.unmodifiable(engines),
          cylinders: List<int>.unmodifiable(cyls),
        );
        count++;
      }
      if (models.isNotEmpty) {
        byBrand[brandName] =
            Map<String, IqCarsModelAdditions>.unmodifiable(models);
        lowerBrand[_key(brandName)] = brandName;
      }
    }
    return IqCarsOverlay._(byBrand, lowerBrand, count);
  }

  /// Parses runtime-asset text. Never throws; garbage yields [empty].
  factory IqCarsOverlay.parse(String raw) {
    final overlay = IqCarsOverlay.fromParsed(parseIqCarsOverlayText(raw));
    return overlay.modelCount == 0 ? empty : overlay;
  }

  final Map<String, Map<String, IqCarsModelAdditions>> _byBrand;
  final Map<String, String> _lowerBrand;

  /// Number of brand + model entries.
  final int modelCount;

  bool get isEmpty => modelCount == 0;

  // Lookup memo: model answers (including "none") are remembered per raw key so
  // repeated Search/Sell rebuilds never re-normalise strings.
  final Map<String, IqCarsModelAdditions?> _lookup =
      <String, IqCarsModelAdditions?>{};

  static String _key(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Keyed Brand + Model lookup. Exact canonical names first, then a
  /// case/whitespace-insensitive match of the SAME names. No fuzzy matching:
  /// `Land Cruiser` and `Land Cruiser Prado` are different keys.
  IqCarsModelAdditions? additionsFor(String? brand, String? model) {
    if (isEmpty || brand == null || model == null) return null;
    final memoKey = '$brand\x1e$model';
    if (_lookup.containsKey(memoKey)) return _lookup[memoKey];
    IqCarsModelAdditions? found;
    final models = _byBrand[brand] ?? _byBrand[_lowerBrand[_key(brand)]];
    if (models != null) {
      found = models[model];
      if (found == null) {
        final wanted = _key(model);
        for (final e in models.entries) {
          if (_key(e.key) == wanted) {
            found = e.value;
            break;
          }
        }
      }
    }
    _lookup[memoKey] = found;
    return found;
  }

  /// Field-specific coverage: does the approved overlay supply at least one
  /// value of this kind for Brand + Model? (O(1): the memoized keyed lookup,
  /// never a scan of the overlay.) An entry for a model does NOT make the model
  /// "covered" for the fields it does not provide.
  bool hasEngineSizes(String? brand, String? model) =>
      additionsFor(brand, model)?.engineVariants.isNotEmpty ?? false;

  bool hasCylinderCounts(String? brand, String? model) =>
      additionsFor(brand, model)?.cylinders.isNotEmpty ?? false;

  bool hasTrims(String? brand, String? model) =>
      additionsFor(brand, model)?.trims.isNotEmpty ?? false;

  /// Every brand -> model entry (read-only view), e.g. for index merges.
  Iterable<MapEntry<String, Map<String, IqCarsModelAdditions>>> get entries =>
      _byBrand.entries;

  // ----------------------------------------------------------------- merges

  /// `baseline` first (unchanged order), then new trims. A trailing `Other`
  /// placeholder stays last, as it always has in the CarNet catalog.
  List<String> mergeTrims(
    List<String> baseline,
    String? brand,
    String? model,
  ) {
    final adds = additionsFor(brand, model)?.trims;
    if (adds == null || adds.isEmpty) return baseline;
    final seen = <String>{for (final t in baseline) _key(t)};
    final fresh = <String>[];
    for (final t in adds) {
      if (seen.add(_key(t))) fresh.add(t);
    }
    if (fresh.isEmpty) return baseline;
    final merged = List<String>.of(baseline);
    final keepOtherLast =
        merged.isNotEmpty && _key(merged.last) == 'other';
    final other = keepOtherLast ? merged.removeLast() : null;
    merged.addAll(fresh);
    if (other != null) merged.add(other);
    return List<String>.unmodifiable(merged);
  }

  /// Adds IQ engine variants to `labels` (catalog labels such as `2.0`,
  /// `3.5 T`, `2.4 D`).
  ///
  /// Identity is displacement + normalized qualifier: `2.4 D`, `2.4 T`, `2.4 TD`
  /// and plain `2.4` are four different engines and none hides another, while
  /// `2.4T` / `2.4 T` / `2.4 Turbo` / `2.4L T` are the same one and appear once.
  /// New variants are written in the app's label style (`2.4 T`); the qualifier
  /// is never dropped and nothing is inferred from it. Existing labels are never
  /// touched or removed.
  ///
  /// Works on a populated OR an empty set (effective = CarNet UNION approved
  /// IQ). Callers must only use this for model-level resolutions, never for a
  /// trim-scoped one (IQ publishes no trim -> engine relationship).
  void addEngineSizes(Set<String> labels, String? brand, String? model) {
    final adds = additionsFor(brand, model)?.engineVariants;
    if (adds == null || adds.isEmpty) return;
    final present = <String>{};
    for (final l in labels) {
      final id = parseEngineIdentity(l);
      if (id != null) present.add('${id.tenths}|${id.qualifier}');
    }
    for (final v in adds) {
      if (present.add(v.identity)) labels.add(v.label);
    }
  }

  /// Adds IQ cylinder counts to `counts` (populated or empty, same union rule
  /// as [addEngineSizes]). Counts are never inferred from displacement.
  void addCylinderCounts(Set<String> counts, String? brand, String? model) {
    final adds = additionsFor(brand, model)?.cylinders;
    if (adds == null || adds.isEmpty) return;
    for (final c in adds) {
      counts.add('$c');
    }
  }

  /// The approved cylinder counts for Brand + Model as picker labels (`'16'`).
  /// Empty when the overlay has none. Used to mark which counts are IQ-approved.
  Set<String> approvedCylinderLabels(String? brand, String? model) {
    final c = additionsFor(brand, model)?.cylinders;
    if (c == null || c.isEmpty) return const <String>{};
    return <String>{for (final x in c) '$x'};
  }

  // ---------------------------------------------------------------- loading

  static Future<IqCarsOverlay>? _loading;

  /// How many times the asset was actually read + parsed (tests assert 1).
  static int loadCount = 0;

  /// The overlay once loaded, else [empty]. Never blocks.
  static IqCarsOverlay get current => _current;
  static IqCarsOverlay _current = empty;

  /// Test seam for the asset text. Null in production ([rootBundle]).
  @visibleForTesting
  static Future<String> Function(String path)? debugAssetLoader;

  /// Loads the runtime asset once (idempotent). Parsing happens off the UI
  /// isolate. Any failure (missing asset, bad JSON) resolves to [empty].
  static Future<IqCarsOverlay> ensureLoaded() => _loading ??= _load();

  static Future<IqCarsOverlay> _load() async {
    loadCount++;
    try {
      final loader = debugAssetLoader;
      final raw = loader != null
          ? await loader(assetPath)
          : await rootBundle.loadString(assetPath);
      final parsed = await compute(parseIqCarsOverlayText, raw);
      _current = IqCarsOverlay.fromParsed(parsed);
      if (_current.isEmpty) _current = empty;
      appLog('IqCarsOverlay: loaded ${_current.modelCount} models');
    } catch (e) {
      _current = empty;
      appLog('IqCarsOverlay: unavailable ($e); using catalog only');
    }
    return _current;
  }

  @visibleForTesting
  static void debugResetForTest() {
    _loading = null;
    _current = empty;
    loadCount = 0;
    debugAssetLoader = null;
  }
}
