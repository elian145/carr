import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/online_spec_variant.dart';

int _jsonInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.parse(v.toString());
}

int? _jsonIntOpt(dynamic v) {
  if (v == null) return null;
  try {
    return _jsonInt(v);
  } catch (_) {
    return null;
  }
}

/// When JSON omits `year_end`, Autodata-style sources mean “still in production”.
/// Cap ranges through the current calendar year + 1 so new model years stay selectable.
int _openEndedModelYearCap() => DateTime.now().year + 1;

/// Bundled JSON often lags by a model year. If the newest [year_end] in the file is still
/// “recent”, we extend catalog years through [_openEndedModelYearCap] and reuse the latest
/// spec row for gap years (same idea as Autodata with no end-of-production date).
const int _kCatalogStaleExportGraceYears = 10;

void _addRecentModelYearTail(Set<int> years) {
  if (years.isEmpty) return;
  final cap = _openEndedModelYearCap();
  var mx = years.first;
  for (final y in years) {
    if (y > mx) mx = y;
  }
  if (mx >= cap - _kCatalogStaleExportGraceYears) {
    for (var y = mx + 1; y <= cap; y++) {
      years.add(y);
    }
  }
}

/// Result of loading [CarSpecIndex] from assets (includes errors for UI / debugging).
class CarSpecIndexLoadResult {
  const CarSpecIndexLoadResult._({this.index, this.errorMessage});
  final CarSpecIndex? index;
  final String? errorMessage;
  bool get isOk => index != null && errorMessage == null;
}

/// Heavy JSON parse + index build; run via [compute] so the UI thread stays responsive.
CarSpecIndexLoadResult parseCarSpecDatasetJsonString(String raw) {
  try {
    final decoded = json.decode(raw);
    if (decoded is! Map<String, dynamic>) {
      return const CarSpecIndexLoadResult._(
        errorMessage: 'Spec database: root must be a JSON object',
      );
    }
    final map = decoded;

    final brands = <_Brand>[];
    for (final e in map['brands'] as List<dynamic>? ?? const []) {
      if (e is! Map<String, dynamic>) continue;
      try {
        brands.add(_Brand.fromJson(e));
      } catch (err, st) {
        debugPrint('CarSpecIndex: skip brand row: $err\n$st');
      }
    }

    final models = <_Model>[];
    for (final e in map['models'] as List<dynamic>? ?? const []) {
      if (e is! Map<String, dynamic>) continue;
      try {
        models.add(_Model.fromJson(e));
      } catch (err, st) {
        debugPrint('CarSpecIndex: skip model row: $err\n$st');
      }
    }

    final trims = <_Trim>[];
    for (final e in map['trims'] as List<dynamic>? ?? const []) {
      if (e is! Map<String, dynamic>) continue;
      try {
        trims.add(_Trim.fromJson(e));
      } catch (err, st) {
        debugPrint('CarSpecIndex: skip trim row: $err\n$st');
      }
    }

    final specByTrimId = <int, _Spec>{};
    for (final e in map['specs'] as List<dynamic>? ?? const []) {
      if (e is! Map<String, dynamic>) continue;
      try {
        final s = _Spec.fromJson(e);
        specByTrimId[s.trimId] = s;
      } catch (err, st) {
        debugPrint('CarSpecIndex: skip spec row: $err\n$st');
      }
    }

    if (brands.isEmpty && models.isEmpty) {
      return const CarSpecIndexLoadResult._(
        errorMessage:
            'Spec database file loaded but contained no brands/models. Re-copy dataset JSON into assets/car_spec_dataset.json and run flutter pub get, then restart the app (not just hot reload).',
      );
    }

    final brandsById = {for (final b in brands) b.id: b};
    final modelsById = {for (final m in models) m.id: m};
    final modelsByBrandId = <int, List<_Model>>{};
    for (final m in models) {
      modelsByBrandId.putIfAbsent(m.brandId, () => []).add(m);
    }
    final trimsByModelId = <int, List<_Trim>>{};
    for (final t in trims) {
      trimsByModelId.putIfAbsent(t.modelId, () => []).add(t);
    }
    for (final e in trimsByModelId.values) {
      e.sort((a, b) => b.yearStart.compareTo(a.yearStart));
    }

    final index = CarSpecIndex._(
      brandsById: brandsById,
      modelsById: modelsById,
      modelsByBrandId: modelsByBrandId,
      trimsByModelId: trimsByModelId,
      specByTrimId: specByTrimId,
    );
    return CarSpecIndexLoadResult._(index: index);
  } catch (e, st) {
    debugPrint('CarSpecIndex parse failed: $e\n$st');
    return CarSpecIndexLoadResult._(
      errorMessage:
          'Could not parse spec database ($e). Ensure assets/car_spec_dataset.json is valid JSON.',
    );
  }
}

/// Parsed automobile-catalog style dataset (brands → models → trims by year → specs).
class CarSpecIndex {
  /// Pass as [appTrim] on catalog autofill APIs to aggregate the **whole model line**
  /// in the spec file (ignore the user’s trim label).
  static const String catalogAutofillModelOnly = '';

  CarSpecIndex._({
    required Map<int, _Brand> brandsById,
    required Map<int, _Model> modelsById,
    required Map<int, List<_Model>> modelsByBrandId,
    required Map<int, List<_Trim>> trimsByModelId,
    required Map<int, _Spec> specByTrimId,
  })  : _brandsById = brandsById,
        _modelsById = modelsById,
        _modelsByBrandId = modelsByBrandId,
        _trimsByModelId = trimsByModelId,
        _specByTrimId = specByTrimId;

  final Map<int, _Brand> _brandsById;
  final Map<int, _Model> _modelsById;
  final Map<int, List<_Model>> _modelsByBrandId;
  final Map<int, List<_Trim>> _trimsByModelId;
  final Map<int, _Spec> _specByTrimId;

  static const assetPath = 'assets/car_spec_dataset.json';

  /// Loads the bundled JSON; surfaces failures instead of failing silently.
  ///
  /// Parsing runs in a background isolate ([compute]) so large datasets do not
  /// freeze the UI isolate. Asset IO still happens on the caller isolate.
  static Future<CarSpecIndexLoadResult> loadWithResult() async {
    try {
      final sw = Stopwatch()..start();
      final raw = await rootBundle.loadString(assetPath);
      if (kDebugMode) {
        debugPrint(
          'CarSpecIndex: read asset ${(raw.length / 1024 / 1024).toStringAsFixed(2)} MiB in ${sw.elapsedMilliseconds} ms',
        );
      }
      final result = await compute(parseCarSpecDatasetJsonString, raw);
      if (kDebugMode) {
        debugPrint(
          'CarSpecIndex: parse + index build finished in ${sw.elapsedMilliseconds} ms (ok=${result.isOk})',
        );
      }
      return result;
    } catch (e, st) {
      debugPrint('CarSpecIndex.loadWithResult failed: $e\n$st');
      return CarSpecIndexLoadResult._(
        errorMessage:
            'Could not load spec database ($e). Ensure assets/car_spec_dataset.json is listed under flutter: assets in pubspec.yaml, then stop the app and run again (full restart).',
      );
    }
  }

  /// Backward-compatible loader (null if anything goes wrong).
  static Future<CarSpecIndex?> load() async {
    final r = await loadWithResult();
    return r.index;
  }

  /// Dataset [Brand.id] for an app catalog brand name, or null if unknown.
  int? datasetBrandId(String appBrand) {
    final key = _normBrand(appBrand);
    for (final b in _brandsById.values) {
      if (_normBrand(b.name) == key) return b.id;
    }
    return null;
  }

  /// Whether this brand + model line appears in the spec dataset (any variant).
  bool hasCoverage(String appBrand, String appModel) {
    final bid = datasetBrandId(appBrand);
    if (bid == null) return false;
    return _familyModels(bid, appModel).isNotEmpty;
  }

  /// Distinct "Brand ModelLine" strings from the dataset (for UI hints).
  List<String> catalogCoverageHints() {
    final out = <String>[];
    for (final entry in _modelsByBrandId.entries) {
      final brand = _brandsById[entry.key];
      if (brand == null) continue;
      final families = entry.value
          .map((m) => _catalogHintFamilyLine(m.name))
          .where((f) => f.isNotEmpty)
          .toSet();
      for (final f in families) {
        out.add('${brand.name} $f');
      }
    }
    out.sort();
    return out;
  }

  /// Short model line for hint text (e.g. "5 Series" not just "5").
  static String _catalogHintFamilyLine(String datasetVariantName) {
    final parts = datasetVariantName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    if (parts.length >= 2 && parts[1].toLowerCase() == 'series') {
      return '${parts[0]} ${parts[1]}';
    }
    return parts.first;
  }

  /// Selectable catalog variants for the app model line (dataset row labels).
  List<CarDatasetVariant> variantsForAppModel(String appBrand, String appModel) {
    final bid = datasetBrandId(appBrand);
    if (bid == null) return const [];
    return _familyModels(bid, appModel)
        .map((m) => CarDatasetVariant(id: m.id, name: m.name))
        .toList();
  }

  /// Dataset rows whose name matches the user trim (e.g. all "Premier" engine rows).
  List<CarDatasetVariant> variantsMatchingAppTrim(
    String appBrand,
    String appModel,
    String appTrim,
  ) {
    final bid = datasetBrandId(appBrand);
    if (bid == null) return const [];
    return _datasetModelsMatchingUserTrim(bid, appModel, appTrim)
        .map((m) => CarDatasetVariant(id: m.id, name: m.name))
        .toList();
  }

  /// The internal per-row catalog variant dropdown is no longer used: specs are unified
  /// in step 2 via [sellFieldOptionsUnion] / [catalogSellSpecVariants] (model line; empty
  /// [appTrim] / [catalogAutofillModelOnly] = whole family). Kept as `false` for compatibility.
  bool showCatalogVariantPickerForTrim(
    String appBrand,
    String appModel,
    String appTrim,
  ) {
    return false;
  }

  /// True when the user's trim label did not match any dataset row name, so spec unions
  /// include the **entire model family** for the year (show a short UI disclaimer).
  bool catalogUsesFullModelFallback(
    String appBrand,
    String appModel,
    String appTrim,
  ) {
    final bid = datasetBrandId(appBrand);
    if (bid == null) return false;
    final t = appTrim.trim();
    if (t.isEmpty) return false;
    final family = _familyModels(bid, appModel);
    if (family.length <= 1) return false;
    final matched = _datasetModelsMatchingUserTrim(bid, appModel, appTrim);
    return matched.isEmpty;
  }

  /// Dataset rows used for catalog years / unions: matched trim rows, or whole family if trim unmatched.
  /// Empty [appTrim] (e.g. [catalogAutofillModelOnly]) always uses the full model line.
  List<CarDatasetVariant> variantsForCatalogSellScope(
    String appBrand,
    String appModel,
    String appTrim,
  ) {
    final bid = datasetBrandId(appBrand);
    if (bid == null) return const [];
    return _modelsForCatalogSellScope(bid, appModel, appTrim)
        .map((m) => CarDatasetVariant(id: m.id, name: m.name))
        .toList();
  }

  /// Years for the catalog card: union across [variantsForCatalogSellScope].
  /// Empty [appTrim] unions years across the full model line ([catalogAutofillModelOnly]).
  List<int> yearsForCatalogStep(
    String appBrand,
    String appModel,
    String appTrim,
  ) {
    final bid = datasetBrandId(appBrand);
    if (bid == null) return const [];
    final models = _modelsForCatalogSellScope(bid, appModel, appTrim);
    if (models.isEmpty) return const [];
    final years = <int>{};
    for (final m in models) {
      for (final row in _trimsByModelId[m.id] ?? const <_Trim>[]) {
        for (var y = row.yearStart; y <= row.yearEnd; y++) {
          years.add(y);
        }
      }
    }
    _addRecentModelYearTail(years);
    final out = years.toList()..sort((a, b) => b.compareTo(a));
    return out;
  }

  /// Distinct equipment rows for [year] across dataset models in scope for [appTrim].
  /// Empty [appTrim] uses the full model line ([catalogAutofillModelOnly]).
  List<OnlineSpecVariant> catalogSellSpecVariants(
    String appBrand,
    String appModel,
    String appTrim,
    int year,
  ) {
    final bid = datasetBrandId(appBrand);
    if (bid == null) return const [];
    final rows = _catalogSellRowsDeduped(bid, appModel, appTrim, year);
    if (rows.isEmpty) return const [];
    _sortCatalogSellRows(rows);
    return rows.map((e) => e.variant).toList();
  }

  /// Default row for catalog apply — matches the first [catalogSellSpecVariants] entry
  /// (deduped equipment, sorted by engine litres then cylinders).
  CatalogSellRepresentative? representativeForCatalogSell(
    String appBrand,
    String appModel,
    String appTrim,
    int year,
  ) {
    final bid = datasetBrandId(appBrand);
    if (bid == null) return null;
    final rows = _catalogSellRowsDeduped(bid, appModel, appTrim, year);
    if (rows.isEmpty) return null;
    _sortCatalogSellRows(rows);
    final r = rows.first;
    return CatalogSellRepresentative(
      datasetModelId: r.datasetModelId,
      fields: r.fields,
    );
  }

  List<({int datasetModelId, CatalogSpecFields fields, OnlineSpecVariant variant})>
      _catalogSellRowsDeduped(
    int brandId,
    String appModel,
    String appTrim,
    int year,
  ) {
    final family = _familyModels(brandId, appModel);
    if (family.isEmpty) return const [];
    final models = _modelsForSellFieldAggregation(brandId, appModel, appTrim, year);
    final anyStrictFamily =
        family.any((m) => _hasStrictTrimCoveringYear(m.id, year));
    final narrowIds = _modelsForCatalogSellScope(brandId, appModel, appTrim)
        .map((m) => m.id)
        .toSet();
    // Only suppress tail-reused MY rows when the user narrowed to a subset of the
    // family. Full-line autofill (empty trim → narrowIds == family) must still union
    // carry-over engines (e.g. 4.0L LC) when another variant has a strict 2025 row.
    final narrowIsStrictSubset = narrowIds.length < family.length;
    final out =
        <({int datasetModelId, CatalogSpecFields fields, OnlineSpecVariant variant})>[];
    final seen = <String>{};
    for (final m in models) {
      if (!_hasStrictTrimCoveringYear(m.id, year)) {
        if (anyStrictFamily &&
            narrowIds.contains(m.id) &&
            narrowIsStrictSubset) {
          continue;
        }
      }
      final trim = _trimForModelYear(m.id, year);
      if (trim == null) continue;
      final spec = _specForTrim(trim.id);
      if (spec == null) continue;
      final CatalogSpecFields f;
      try {
        f = _mapSpecToFormFields(
          spec,
          catalogLabelHint: '${m.name} ${trim.name}',
        );
      } catch (_) {
        continue;
      }
      final key = <String?>[
        f.engineSizeLiters?.toStringAsFixed(2),
        f.displacementSuffix,
        f.cylinderCount?.toString(),
        f.transmission,
        f.driveType,
        f.bodyType,
        f.engineType,
        f.fuelType,
        f.seating?.toString(),
        f.fuelEconomy,
      ].join('|');
      if (!seen.add(key)) continue;
      out.add((
        datasetModelId: m.id,
        fields: f,
        variant: OnlineSpecVariant(
          engineSizeLiters: f.engineSizeLiters,
          displacementSuffix: f.displacementSuffix,
          cylinderCount: f.cylinderCount,
          seating: f.seating,
          fuelEconomy: f.fuelEconomy,
          transmission: f.transmission,
          drivetrain: f.driveType,
          bodyType: f.bodyType,
          engineType: f.engineType,
          fuelType: f.fuelType,
        ),
      ));
    }
    return out;
  }

  void _sortCatalogSellRows(
    List<({int datasetModelId, CatalogSpecFields fields, OnlineSpecVariant variant})>
        rows,
  ) {
    rows.sort((a, b) {
      final ae = a.variant.engineSizeLiters ?? 0;
      final be = b.variant.engineSizeLiters ?? 0;
      final c = ae.compareTo(be);
      if (c != 0) return c;
      return (a.variant.cylinderCount ?? 0).compareTo(b.variant.cylinderCount ?? 0);
    });
  }

  List<_Model> _familyModels(int brandId, String appModel) {
    final fam = appModel.trim();
    if (fam.isEmpty) return [];
    final famLower = fam.toLowerCase();
    final list = _modelsByBrandId[brandId] ?? [];
    return list
        .where((m) => _datasetNameMatchesAppFamily(m.name, famLower))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// True when [datasetVariantName] belongs to the app catalog model line [familyLower].
  ///
  /// Supports multi-word lines (e.g. app "5 Series" ↔ dataset "5 Series 540i …") and
  /// single-word lines (e.g. "Sportage" ↔ "Sportage 2 0 …") via first-token match.
  static bool _datasetNameMatchesAppFamily(
    String datasetVariantName,
    String familyLower,
  ) {
    final dn = datasetVariantName.trim().toLowerCase();
    if (dn.isEmpty) return false;
    if (dn == familyLower) return true;
    if (dn.startsWith('$familyLower ')) return true;
    final first = dn.split(RegExp(r'\s+')).first;
    return first == familyLower;
  }

  /// Score how well a dataset variant name matches the app trim label.
  static double trimMatchScore(String datasetVariantName, String appTrim) {
    final v = datasetVariantName.toLowerCase();
    final t = appTrim.toLowerCase();
    if (t.isEmpty || t == 'base' || t == 'other') return 0;
    var s = 0.0;
    final parts = t
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .split(' ')
        .where((p) => p.isNotEmpty);
    for (final p in parts) {
      if (p.length >= 2 && v.contains(p)) s += 2.5;
      if (p.length == 1 && (p == 's' || p == 'x') && v.contains(' $p')) s += 1.0;
    }
    if (t.contains('x-line') && v.contains('x-line')) s += 4;
    if (t.contains('gt') && v.contains('gt-line')) s += 3;
    if (t.contains('crdi') && v.contains('crdi')) s += 3;
    if (t.contains('lx') && v.contains('lx')) s += 2;
    if (t.contains('ex') && v.contains(' ex')) s += 2;
    if (t.contains('sx') && v.contains('sx')) s += 2;
    return s;
  }

  /// Pick default dataset model for the family + trim; null if no coverage.
  /// Empty [appTrim] picks the first dataset row in the family (sorted by name).
  int? suggestDatasetModelId(int brandId, String appModel, String appTrim) {
    final fam = _familyModels(brandId, appModel);
    if (fam.isEmpty) return null;
    if (fam.length == 1) return fam.first.id;
    if (appTrim.trim().isEmpty) return fam.first.id;
    final scored = fam
        .map((m) => MapEntry(m.id, trimMatchScore(m.name, appTrim)))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return scored.first.key;
  }

  /// True if [year] is covered by raw ranges or by [recent export tail] logic.
  bool datasetVariantCoversYear(int datasetModelId, int year) {
    return _trimForModelYear(datasetModelId, year) != null;
  }

  /// Production years for UI hints, e.g. `2017–2023` or `2020`.
  String datasetVariantProductionRangeLabel(int datasetModelId) {
    final rows = _trimsByModelId[datasetModelId] ?? [];
    if (rows.isEmpty) return '';
    final t = rows.first;
    if (t.yearStart == t.yearEnd) return '${t.yearStart}';
    return '${t.yearStart}–${t.yearEnd}';
  }

  /// Best variant that matches [appTrim] and includes [formYear] when possible;
  /// otherwise same as [suggestDatasetModelId].
  int? suggestDatasetModelIdForFormYear(
    String appBrand,
    String appModel,
    String appTrim,
    int? formYear,
  ) {
    final bid = datasetBrandId(appBrand);
    if (bid == null) return null;
    final all = variantsForAppModel(appBrand, appModel);
    if (all.isEmpty) return null;

    if (formYear != null) {
      final rep =
          representativeForCatalogSell(appBrand, appModel, appTrim, formYear);
      if (rep != null) return rep.datasetModelId;
    }

    final fallback = suggestDatasetModelId(bid, appModel, appTrim) ?? all.first.id;
    if (formYear == null) return fallback;

    final covering = <CarDatasetVariant>[];
    for (final v in all) {
      final m = _modelsById[v.id];
      if (m == null) continue;
      if (!_trimMatchesUserLabel(appTrim, m)) continue;
      if (!datasetVariantCoversYear(v.id, formYear)) continue;
      covering.add(v);
    }
    if (covering.isEmpty) {
      for (final v in all) {
        if (datasetVariantCoversYear(v.id, formYear)) return v.id;
      }
      return fallback;
    }
    if (covering.length == 1) return covering.first.id;
    final scored = covering
        .map((v) => MapEntry(v.id, trimMatchScore(v.name, appTrim)))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return scored.first.key;
  }

  List<int> yearsForModel(int datasetModelId) {
    final rows = _trimsByModelId[datasetModelId] ?? [];
    final years = <int>{};
    for (final t in rows) {
      for (var y = t.yearStart; y <= t.yearEnd; y++) {
        years.add(y);
      }
    }
    _addRecentModelYearTail(years);
    final out = years.toList()..sort((a, b) => b.compareTo(a));
    return out;
  }

  /// Years that appear in the catalog for this brand + model line + user trim (union across matching dataset rows).
  List<int> yearsForAppTrimSelection(String appBrand, String appModel, String appTrim) {
    final bid = datasetBrandId(appBrand);
    if (bid == null) return const [];
    final models = _datasetModelsMatchingUserTrim(bid, appModel, appTrim);
    if (models.isEmpty) return const [];
    final years = <int>{};
    for (final m in models) {
      for (final row in _trimsByModelId[m.id] ?? const <_Trim>[]) {
        for (var y = row.yearStart; y <= row.yearEnd; y++) {
          years.add(y);
        }
      }
    }
    _addRecentModelYearTail(years);
    final out = years.toList()..sort((a, b) => b.compareTo(a));
    return out;
  }

  /// Union of sell-step values for every catalog row that matches brand, model family, trim, and [year].
  /// Empty [appTrim] unions the full model line ([catalogAutofillModelOnly]).
  /// Null when there is no coverage or no spec rows for that year.
  CatalogSellFieldOptions? sellFieldOptionsUnion(
    String appBrand,
    String appModel,
    String appTrim,
    int year,
  ) {
    final bid = datasetBrandId(appBrand);
    if (bid == null) return null;
    final family = _familyModels(bid, appModel);
    if (family.isEmpty) return null;
    final models = _modelsForSellFieldAggregation(bid, appModel, appTrim, year);
    if (models.isEmpty) return null;
    final anyStrictFamily =
        family.any((m) => _hasStrictTrimCoveringYear(m.id, year));
    final narrowIds = _modelsForCatalogSellScope(bid, appModel, appTrim)
        .map((m) => m.id)
        .toSet();
    final narrowIsStrictSubset = narrowIds.length < family.length;

    final transmissions = <String>{};
    final fuelTypes = <String>{};
    final bodyTypes = <String>{};
    final driveTypes = <String>{};
    final cylinderCounts = <String>{};
    final engineSizes = <String>{};
    final seatings = <String>{};

    var anySpec = false;
    for (final m in models) {
      if (!_hasStrictTrimCoveringYear(m.id, year)) {
        if (anyStrictFamily &&
            narrowIds.contains(m.id) &&
            narrowIsStrictSubset) {
          continue;
        }
      }
      final trim = _trimForModelYear(m.id, year);
      if (trim == null) continue;
      final spec = _specForTrim(trim.id);
      if (spec == null) continue;
      anySpec = true;
      final f = _mapSpecToFormFields(
        spec,
        catalogLabelHint: '${m.name} ${trim.name}',
      );
      transmissions.add(sellFlowTransmissionLabel(f.transmission));
      fuelTypes.add(sellFlowFuelLabel(f.fuelType));
      bodyTypes.add(sellFlowBodyLabel(f.bodyType));
      driveTypes.add(sellFlowDriveLabel(f.driveType));
      if (f.cylinderCount != null && f.cylinderCount! > 0) {
        cylinderCounts.add('${f.cylinderCount}');
      }
      if (f.engineSizeLiters != null && f.engineSizeLiters! > 0) {
        engineSizes.add(
          '${f.engineSizeLiters!.toStringAsFixed(1)}${f.displacementSuffix}',
        );
      }
      final seatLabel = sellFlowNearestSeatingLabel(f.seating);
      if (seatLabel != null) seatings.add(seatLabel);
    }

    if (!anySpec) return null;
    return CatalogSellFieldOptions(
      transmissions: transmissions,
      fuelTypes: fuelTypes,
      bodyTypes: bodyTypes,
      driveTypes: driveTypes,
      cylinderCounts: cylinderCounts,
      engineSizes: engineSizes,
      seatings: seatings,
    );
  }

  /// Engine-size labels and cylinder counts unioned across catalog years for
  /// [appBrand] + [appModel]. Empty [appTrim] uses the full model line
  /// ([catalogAutofillModelOnly]); a non-empty trim narrows via the same rules as
  /// [sellFieldOptionsUnion].
  ///
  /// When [rangeMinYear] and/or [rangeMaxYear] are set, only those model years are
  /// included (inclusive). If that window excludes every catalog year, returns empty
  /// lists so the UI can show only "Any".
  ///
  /// Returns null when there is no model coverage, or when there are years in scope
  /// but no spec rows with engine/cylinder data.
  ({List<String> engineSizes, List<String> cylinderCounts})?
      homeFilterEngineCylinderOptions(
    String appBrand,
    String appModel,
    String appTrim, {
    int? rangeMinYear,
    int? rangeMaxYear,
  }) {
    if (!hasCoverage(appBrand, appModel)) return null;
    final years = yearsForCatalogStep(appBrand, appModel, appTrim);
    if (years.isEmpty) return null;
    var yearList = years;
    if (rangeMinYear != null || rangeMaxYear != null) {
      final lo = rangeMinYear;
      final hi = rangeMaxYear;
      yearList = years
          .where(
            (y) => (lo == null || y >= lo) && (hi == null || y <= hi),
          )
          .toList();
    }
    if (yearList.isEmpty) {
      return (engineSizes: <String>[], cylinderCounts: <String>[]);
    }
    final engines = <String>{};
    final cylinders = <String>{};
    var anyRow = false;
    for (final y in yearList) {
      final o = sellFieldOptionsUnion(appBrand, appModel, appTrim, y);
      if (o == null) continue;
      anyRow = true;
      engines.addAll(o.engineSizes);
      cylinders.addAll(o.cylinderCounts);
    }
    if (!anyRow) return null;
    final engList = engines.toList()
      ..sort((a, b) {
        final ae = OnlineSpecVariant.parseLeadingEngineLiters(a) ?? 0;
        final be = OnlineSpecVariant.parseLeadingEngineLiters(b) ?? 0;
        final c = ae.compareTo(be);
        if (c != 0) return c;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    final cylList = cylinders.toList()
      ..sort((a, b) {
        final ia = int.tryParse(a) ?? 0;
        final ib = int.tryParse(b) ?? 0;
        return ia.compareTo(ib);
      });
    return (engineSizes: engList, cylinderCounts: cylList);
  }

  /// Deduped [OnlineSpecVariant] rows across all catalog years in scope for home filters
  /// (same year window as [homeFilterEngineCylinderOptions]).
  List<OnlineSpecVariant> homeFilterSpecVariantsUnion(
    String appBrand,
    String appModel,
    String appTrim, {
    int? rangeMinYear,
    int? rangeMaxYear,
  }) {
    if (!hasCoverage(appBrand, appModel)) return const [];
    final years = yearsForCatalogStep(appBrand, appModel, appTrim);
    if (years.isEmpty) return const [];
    var yearList = years;
    if (rangeMinYear != null || rangeMaxYear != null) {
      final lo = rangeMinYear;
      final hi = rangeMaxYear;
      yearList = years
          .where(
            (y) => (lo == null || y >= lo) && (hi == null || y <= hi),
          )
          .toList();
    }
    if (yearList.isEmpty) return const [];
    final seen = <String>{};
    final out = <OnlineSpecVariant>[];
    for (final y in yearList) {
      for (final v in catalogSellSpecVariants(appBrand, appModel, appTrim, y)) {
        final key = _homeFilterVariantDedupeKey(v);
        if (seen.add(key)) {
          out.add(v);
        }
      }
    }
    out.sort((a, b) {
      final ae = a.engineSizeLiters ?? 0;
      final be = b.engineSizeLiters ?? 0;
      final c = ae.compareTo(be);
      if (c != 0) return c;
      return (a.cylinderCount ?? 0).compareTo(b.cylinderCount ?? 0);
    });
    return out;
  }

  static String _homeFilterVariantDedupeKey(OnlineSpecVariant v) {
    return <String?>[
      v.engineSizeLiters?.toStringAsFixed(2),
      v.displacementSuffix,
      v.cylinderCount?.toString(),
      v.transmission,
      v.drivetrain,
      v.bodyType,
      v.engineType,
      v.fuelType,
      v.seating?.toString(),
      v.fuelEconomy,
    ].join('|');
  }

  static const double _kMinTrimMatchScore = 2.0;

  bool _trimMatchesUserLabel(String appTrim, _Model m) {
    final t = appTrim.trim().toLowerCase();
    if (t.isEmpty) return false;
    if (t == 'base' || t == 'other') return true;
    return trimMatchScore(m.name, appTrim) >= _kMinTrimMatchScore;
  }

  List<_Model> _datasetModelsMatchingUserTrim(int brandId, String appModel, String appTrim) {
    return _familyModels(brandId, appModel).where((m) => _trimMatchesUserLabel(appTrim, m)).toList();
  }

  /// Trim-matching dataset rows when possible; otherwise the full model line (supplier
  /// strings often omit marketing trims like GX / regional badges).
  List<_Model> _modelsForCatalogSellScope(int brandId, String appModel, String appTrim) {
    final family = _familyModels(brandId, appModel);
    if (family.isEmpty) return const [];
    final t = appTrim.trim();
    if (t.isEmpty) return family;
    final matched =
        family.where((m) => _trimMatchesUserLabel(appTrim, m)).toList();
    if (matched.isNotEmpty) return matched;
    return family;
  }

  /// Raw JSON range only (no tail-year fallback) — used to decide real MY coverage.
  bool _hasStrictTrimCoveringYear(int modelId, int year) {
    for (final t in _trimsByModelId[modelId] ?? const <_Trim>[]) {
      if (t.coversYear(year)) return true;
    }
    return false;
  }

  /// Models to aggregate fuel/engine/drivetrain options: trim scope plus any same-line
  /// variant that has a **real** catalog row for [year] (so e.g. VX trim still picks up
  /// hybrid LC 300 for 2025 even when "VX" does not appear in that dataset name).
  List<_Model> _modelsForSellFieldAggregation(
    int brandId,
    String appModel,
    String appTrim,
    int year,
  ) {
    final family = _familyModels(brandId, appModel);
    if (family.isEmpty) return const [];
    final narrow = _modelsForCatalogSellScope(brandId, appModel, appTrim);
    final ids = <int>{};
    for (final m in narrow) {
      ids.add(m.id);
    }
    for (final m in family) {
      if (_hasStrictTrimCoveringYear(m.id, year)) {
        ids.add(m.id);
      }
    }
    return family.where((m) => ids.contains(m.id)).toList();
  }

  _Trim? _trimForModelYear(int datasetModelId, int year) {
    final rows = _trimsByModelId[datasetModelId] ?? const <_Trim>[];
    for (final t in rows) {
      if (t.coversYear(year)) return t;
    }
    final cap = _openEndedModelYearCap();
    if (year > cap) return null;
    _Trim? best;
    for (final t in rows) {
      if (t.yearStart > year) continue;
      if (best == null || t.yearEnd > best.yearEnd) best = t;
    }
    if (best != null &&
        year > best.yearEnd &&
        best.yearEnd >= cap - _kCatalogStaleExportGraceYears) {
      return best;
    }
    return null;
  }

  _Spec? _specForTrim(int trimId) => _specByTrimId[trimId];

  /// Resolved specs for a dataset model row and model year, or null if missing.
  CatalogSpecFields? appliedFieldsFor(int datasetModelId, int year) {
    final trim = _trimForModelYear(datasetModelId, year);
    if (trim == null) return null;
    final spec = _specForTrim(trim.id);
    if (spec == null) return null;
    final model = _modelsById[datasetModelId];
    final hint =
        model != null ? '${model.name} ${trim.name}' : trim.name;
    try {
      return _mapSpecToFormFields(spec, catalogLabelHint: hint);
    } catch (e, st) {
      debugPrint('CarSpecIndex.appliedFieldsFor failed: $e\n$st');
      return null;
    }
  }

  static String _catalogDisplacementBadgeContext(_Spec s, String catalogHint) {
    final b = StringBuffer()
      ..write(catalogHint)
      ..write(' ')
      ..write(s.fuelType ?? '')
      ..write(' ')
      ..write(s.transmission ?? '')
      ..write(' ')
      ..write(s.drivetrain ?? '')
      ..write(' ')
      ..write(s.bodyType ?? '')
      ..write(' ');
    for (final e in s.rawPairs.entries) {
      b
        ..write(e.key)
        ..write(' ')
        ..write(e.value)
        ..write(' ');
    }
    return b.toString().toLowerCase();
  }

  static bool _catalogTextImpliesTurbo(String blob) {
    final t = blob;
    if (t.contains('supercharger') || t.contains('kompressor')) return false;
    if (t.contains('naturally aspirated')) return false;
    const hints = <String>[
      'turbo',
      'twin turbo',
      'twinturbo',
      'twin-turbo',
      'biturbo',
      'quad turbo',
      'tdi',
      'tfsi',
      'ecoboost',
      'gtd',
      'tgdi',
      'd-4d',
      'd4d',
      'cdti',
      'crdi',
      'hdi',
      'bluehdi',
      'blue hdi',
      'i-force',
      'iforce',
    ];
    for (final h in hints) {
      if (t.contains(h)) return true;
    }
    if (t.contains('tsi') && !t.contains('fsi')) return true;
    return false;
  }

  /// `" D"`, `" T"`, `" TD"`, or `""` for sell-flow engine size labels.
  static String _displacementBadgeSuffix({
    required String fuelTypeField,
    required _Spec s,
    required String catalogLabelHint,
  }) {
    final diesel = fuelTypeField == 'diesel';
    final blob = _catalogDisplacementBadgeContext(s, catalogLabelHint);
    final turbo = _catalogTextImpliesTurbo(blob);
    if (diesel && turbo) return ' TD';
    if (diesel) return ' D';
    if (turbo) return ' T';
    return '';
  }

  /// Autodata-style dataset names often use a space instead of a decimal point
  /// (`3 5L` = 3.5 L) while [displacement_cc] is exact (e.g. 3445 cm³ → 3.4 when
  /// rounded to one decimal). When [catalogLabelHint] contains a nominal size
  /// that matches the measured displacement (~±0.2 L), prefer the label so the app
  /// matches supplier websites and marketing trim names.
  static CatalogSpecFields _mapSpecToFormFields(
    _Spec s, {
    String? catalogLabelHint,
  }) {
    final raw = s.rawPairs;

    final ft = (s.fuelType ?? '').toLowerCase();
    String engineType = 'gasoline';
    String fuelTypeField = 'gasoline';
    if (ft.contains('diesel')) {
      engineType = 'diesel';
      fuelTypeField = 'diesel';
    } else if (ft.contains('electric') && !ft.contains('hybrid')) {
      engineType = 'electric';
      fuelTypeField = 'electric';
    } else if (ft.contains('hybrid')) {
      engineType = 'hybrid';
      fuelTypeField = 'hybrid';
    }

    String transmission = 'automatic';
    final ts = (s.transmission ?? '').toLowerCase();
    if (ts.contains('manual')) transmission = 'manual';

    String driveType = 'fwd';
    final traction = (raw['Traction:'] ?? '').toString().toLowerCase();
    final dr = '${s.drivetrain ?? ''} $traction'.toLowerCase();
    if (dr.contains('awd')) {
      driveType = 'awd';
    } else if (dr.contains('4wd') || dr.contains('4-wd')) {
      driveType = '4wd';
    } else if (dr.contains('rwd') || dr.contains('rear-wheel')) {
      driveType = 'rwd';
    } else if (dr.contains('fwd') || dr.contains('front-wheel')) {
      driveType = 'fwd';
    }

    String bodyType = 'sedan';
    final b = (s.bodyType ?? '').toLowerCase();
    if (b.contains('suv') ||
        b.contains('sport-utility') ||
        b.contains('off-road') ||
        (b.contains('wagon') && b.contains('sport'))) {
      bodyType = 'suv';
    } else if (b.contains('hatch')) {
      bodyType = 'hatchback';
    } else if (b.contains('coupe')) {
      bodyType = 'coupe';
    } else if (b.contains('pickup') || b.contains('truck')) {
      bodyType = 'pickup';
    } else if (b.contains('van')) {
      bodyType = 'van';
    } else if (b.contains('sedan') || b.contains('saloon')) {
      bodyType = 'sedan';
    }

    final engineLiters = _resolveEngineLitersForForm(
      s,
      raw,
      catalogLabelHint,
    );

    final displacementSuffix = engineLiters != null && engineLiters > 0.001
        ? _displacementBadgeSuffix(
            fuelTypeField: fuelTypeField,
            s: s,
            catalogLabelHint: catalogLabelHint ?? '',
          )
        : '';

    int? cylinders = _parseCylinderCount(raw['Cylinders alignment:']?.toString());

    int? seating = s.seats;
    if (seating != null && seating <= 0) seating = null;

    String? fuelEconomy;
    final l100 = s.fuelConsumptionL100km;
    if (l100 != null && l100 >= 3 && l100 <= 25) {
      fuelEconomy = '${l100.toStringAsFixed(1)} L/100km (combined est.)';
    }
    final nedc = raw['EU NEDC/Australia ADR82:']?.toString();
    if (nedc != null && nedc.contains('l/100km')) {
      fuelEconomy = nedc;
    }

    return CatalogSpecFields(
      engineType: engineType,
      fuelType: fuelTypeField,
      transmission: transmission,
      driveType: driveType,
      bodyType: bodyType,
      engineSizeLiters: engineLiters,
      displacementSuffix: displacementSuffix,
      cylinderCount: cylinders,
      fuelEconomy: fuelEconomy,
      seating: seating,
    );
  }

  static String _normBrand(String s) => s.toLowerCase().trim();

  /// Parses nominal displacement from a dataset model/trim label (e.g. `3 5L`, `2 25L`,
  /// `2 4 i-force`, `3 0 d-4d`, `4 0 v6`, `4 0 (`).
  static double? _nominalLitersFromCatalogLabel(String? label) {
    if (label == null) return null;
    final n = label.toLowerCase();
    if (n.isEmpty) return null;
    var m = RegExp(r'(\d+\.\d+)\s*l(?:iter)?\b').firstMatch(n);
    if (m != null) return double.tryParse(m.group(1)!);
    m = RegExp(r'\b(\d)\s+(\d{2})\s*l(?:iter)?\b').firstMatch(n);
    if (m != null) {
      final a = int.tryParse(m.group(1)!);
      final b = int.tryParse(m.group(2)!);
      if (a == null || b == null) return null;
      return a + b / 100.0;
    }
    m = RegExp(r'\b(\d)\s+(\d)\s*l(?:iter)?\b').firstMatch(n);
    if (m != null) {
      final a = int.tryParse(m.group(1)!);
      final b = int.tryParse(m.group(2)!);
      if (a == null || b == null) return null;
      return a + b / 10.0;
    }
    // No literal "L": Toyota/Autodata style `2 4 i-force max`, `3 5 v6 i-force`, etc.
    m = RegExp(
      r'\b(\d)\s+(\d)\s+(?!l(?:iter)?\b)(?=[a-z0-9(])',
      caseSensitive: false,
    ).firstMatch(n);
    if (m != null) {
      final a = int.tryParse(m.group(1)!);
      final b = int.tryParse(m.group(2)!);
      if (a == null || b == null) return null;
      return a + b / 10.0;
    }
    return null;
  }

  static double? _resolveEngineLitersForForm(
    _Spec s,
    Map<String, String> raw,
    String? catalogLabelHint,
  ) {
    double? fromCc;
    if (s.displacementCc != null && s.displacementCc! > 0) {
      fromCc = s.displacementCc! / 1000.0;
    } else {
      fromCc = _parseDisplacementLiters(raw['Displacement:']?.toString());
    }
    final fromName = _nominalLitersFromCatalogLabel(catalogLabelHint);
    if (fromName != null && fromCc != null) {
      if ((fromName - fromCc).abs() <= 0.2) return fromName;
      return fromCc;
    }
    return fromCc ?? fromName;
  }

  static double? _parseDisplacementLiters(String? text) {
    if (text == null) return null;
    final lower = text.toLowerCase();
    final cm = RegExp(r'(\d+)\s*cm3').firstMatch(lower);
    if (cm != null) {
      final cc = int.tryParse(cm.group(1)!);
      if (cc != null) return cc / 1000.0;
    }
    final lit = RegExp(r'(\d+(\.\d+)?)\s*l(?:iter)?\b').firstMatch(lower);
    if (lit != null) return double.tryParse(lit.group(1)!);
    return null;
  }

  static int? _parseCylinderCount(String? text) {
    if (text == null) return null;
    final m = RegExp(r'(?:line|inline|v|w|boxer)\s*(\d+)', caseSensitive: false)
        .firstMatch(text);
    if (m != null) return int.tryParse(m.group(1)!);
    final tail = RegExp(r'\b(\d+)\s*$').firstMatch(text.trim());
    if (tail != null) return int.tryParse(tail.group(1)!);
    return null;
  }
}

class CarDatasetVariant {
  const CarDatasetVariant({required this.id, required this.name});
  final int id;
  final String name;
}

class CatalogSpecFields {
  const CatalogSpecFields({
    required this.engineType,
    required this.fuelType,
    required this.transmission,
    required this.driveType,
    required this.bodyType,
    this.engineSizeLiters,
    this.displacementSuffix = '',
    this.cylinderCount,
    this.fuelEconomy,
    this.seating,
  });

  final String engineType;
  final String fuelType;
  final String transmission;
  final String driveType;
  final String bodyType;
  final double? engineSizeLiters;
  /// Display only, e.g. `" D"`, `" T"`, `" TD"`.
  final String displacementSuffix;
  final int? cylinderCount;
  final String? fuelEconomy;
  final int? seating;
}

/// Default dataset row for catalog apply / preview — same as the first item in
/// [CarSpecIndex.catalogSellSpecVariants] (deduped, sorted by engine size).
class CatalogSellRepresentative {
  const CatalogSellRepresentative({
    required this.datasetModelId,
    required this.fields,
  });
  final int datasetModelId;
  final CatalogSpecFields fields;
}

/// Allowed sell-flow labels derived from the spec DB (matches SellStep2 pick lists).
class CatalogSellFieldOptions {
  const CatalogSellFieldOptions({
    required this.transmissions,
    required this.fuelTypes,
    required this.bodyTypes,
    required this.driveTypes,
    required this.cylinderCounts,
    required this.engineSizes,
    required this.seatings,
  });

  final Set<String> transmissions;
  final Set<String> fuelTypes;
  final Set<String> bodyTypes;
  final Set<String> driveTypes;
  final Set<String> cylinderCounts;
  final Set<String> engineSizes;
  final Set<String> seatings;
}

/// Sell step 2 picker label for transmission (internal API value from [CatalogSpecFields]).
String sellFlowTransmissionLabel(String api) {
  switch (api.toLowerCase()) {
    case 'manual':
      return 'Manual';
    default:
      return 'Automatic';
  }
}

String sellFlowFuelLabel(String api) {
  switch (api.toLowerCase()) {
    case 'diesel':
      return 'Diesel';
    case 'electric':
      return 'Electric';
    case 'hybrid':
      return 'Hybrid';
    default:
      return 'Gasoline';
  }
}

String sellFlowBodyLabel(String api) {
  switch (api.toLowerCase()) {
    case 'suv':
      return 'SUV';
    case 'hatchback':
      return 'Hatchback';
    case 'coupe':
      return 'Coupe';
    case 'pickup':
      return 'Pickup';
    case 'van':
      return 'Van';
    default:
      return 'Sedan';
  }
}

String sellFlowDriveLabel(String api) {
  switch (api.toLowerCase()) {
    case 'rwd':
      return 'RWD';
    case 'awd':
      return 'AWD';
    case '4wd':
      return '4WD';
    default:
      return 'FWD';
  }
}

const List<String> _kSellFlowSeatOptions = ['2', '4', '5', '6', '7', '8'];

String? sellFlowNearestSeatingLabel(int? seats) {
  if (seats == null || seats <= 0) return null;
  final s = '$seats';
  if (_kSellFlowSeatOptions.contains(s)) return s;
  if (seats <= 2) return '2';
  if (seats <= 4) return '4';
  if (seats <= 5) return '5';
  if (seats <= 6) return '6';
  if (seats <= 7) return '7';
  return '8';
}

class _Brand {
  _Brand({required this.id, required this.name});
  final int id;
  final String name;

  static _Brand fromJson(Map<String, dynamic> j) => _Brand(
        id: _jsonInt(j['id']),
        name: (j['name'] ?? '').toString(),
      );
}

class _Model {
  _Model({required this.id, required this.brandId, required this.name});
  final int id;
  final int brandId;
  final String name;

  static _Model fromJson(Map<String, dynamic> j) => _Model(
        id: _jsonInt(j['id']),
        brandId: _jsonInt(j['brand_id']),
        name: (j['name'] ?? '').toString(),
      );
}

class _Trim {
  _Trim({
    required this.id,
    required this.modelId,
    required this.yearStart,
    required this.yearEnd,
    required this.name,
  });

  final int id;
  final int modelId;
  /// First model year (JSON `year`).
  final int yearStart;
  /// Last model year inclusive (`year_end` in JSON; if omitted, still in production → current year + 1).
  final int yearEnd;
  final String name;

  /// Representative year for sorting / legacy callers (same as [yearStart]).
  int get year => yearStart;

  bool coversYear(int y) => y >= yearStart && y <= yearEnd;

  static _Trim fromJson(Map<String, dynamic> j) {
    final ys = _jsonInt(j['year']);
    var ye = _jsonIntOpt(j['year_end']);
    if (ye != null && ye < ys) {
      ye = ys;
    }
    if (ye == null) {
      final cap = _openEndedModelYearCap();
      ye = ys > cap ? ys : cap;
    }
    return _Trim(
      id: _jsonInt(j['id']),
      modelId: _jsonInt(j['model_id']),
      yearStart: ys,
      yearEnd: ye,
      name: (j['name'] ?? '').toString(),
    );
  }
}

class _Spec {
  _Spec({
    required this.trimId,
    this.displacementCc,
    this.fuelType,
    this.transmission,
    this.drivetrain,
    this.bodyType,
    this.seats,
    this.fuelConsumptionL100km,
    required this.rawPairs,
  });

  final int trimId;
  final int? displacementCc;
  final String? fuelType;
  final String? transmission;
  final String? drivetrain;
  final String? bodyType;
  final int? seats;
  final double? fuelConsumptionL100km;
  final Map<String, String> rawPairs;

  static _Spec fromJson(Map<String, dynamic> j) {
    final raw = j['raw_spec_pairs'];
    final pairs = <String, String>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        pairs['${k ?? ''}'] = '${v ?? ''}';
      });
    }
    return _Spec(
      trimId: _jsonInt(j['trim_id']),
      displacementCc: _jsonIntOpt(j['displacement_cc']),
      fuelType: j['fuel_type']?.toString(),
      transmission: j['transmission']?.toString(),
      drivetrain: j['drivetrain']?.toString(),
      bodyType: j['body_type']?.toString(),
      seats: _jsonIntOpt(j['seats']),
      fuelConsumptionL100km: (j['fuel_consumption_l_100km'] as num?)?.toDouble(),
      rawPairs: pairs,
    );
  }
}
