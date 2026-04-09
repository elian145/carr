import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
      e.sort((a, b) => b.year.compareTo(a.year));
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
          .map((m) {
            final parts = m.name.trim().split(RegExp(r'\s+'));
            if (parts.isEmpty) return '';
            return parts.first;
          })
          .where((f) => f.isNotEmpty)
          .toSet();
      for (final f in families) {
        out.add('${brand.name} $f');
      }
    }
    out.sort();
    return out;
  }

  /// Selectable catalog variants for the app model line (dataset row labels).
  List<CarDatasetVariant> variantsForAppModel(String appBrand, String appModel) {
    final bid = datasetBrandId(appBrand);
    if (bid == null) return const [];
    return _familyModels(bid, appModel)
        .map((m) => CarDatasetVariant(id: m.id, name: m.name))
        .toList();
  }

  List<_Model> _familyModels(int brandId, String appModel) {
    final fam = appModel.trim();
    if (fam.isEmpty) return [];
    final fl = fam.toLowerCase();
    final list = _modelsByBrandId[brandId] ?? [];
    return list.where((m) {
      final first = m.name.split(RegExp(r'\s+')).first.toLowerCase();
      return first == fl;
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
  int? suggestDatasetModelId(int brandId, String appModel, String appTrim) {
    final fam = _familyModels(brandId, appModel);
    if (fam.isEmpty) return null;
    if (fam.length == 1) return fam.first.id;
    final scored = fam
        .map((m) => MapEntry(m.id, trimMatchScore(m.name, appTrim)))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return scored.first.key;
  }

  List<int> yearsForModel(int datasetModelId) {
    final rows = _trimsByModelId[datasetModelId] ?? [];
    final ys = rows.map((t) => t.year).toSet().toList()..sort((a, b) => b.compareTo(a));
    return ys;
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
        years.add(row.year);
      }
    }
    final out = years.toList()..sort((a, b) => b.compareTo(a));
    return out;
  }

  /// Union of sell-step values for every catalog row that matches brand, model family, trim, and [year].
  /// Null when there is no coverage or no spec rows for that year.
  CatalogSellFieldOptions? sellFieldOptionsUnion(
    String appBrand,
    String appModel,
    String appTrim,
    int year,
  ) {
    final bid = datasetBrandId(appBrand);
    if (bid == null) return null;
    final models = _datasetModelsMatchingUserTrim(bid, appModel, appTrim);
    if (models.isEmpty) return null;

    final transmissions = <String>{};
    final fuelTypes = <String>{};
    final bodyTypes = <String>{};
    final driveTypes = <String>{};
    final cylinderCounts = <String>{};
    final engineSizes = <String>{};
    final seatings = <String>{};

    var anySpec = false;
    for (final m in models) {
      final trim = _trimForModelYear(m.id, year);
      if (trim == null) continue;
      final spec = _specForTrim(trim.id);
      if (spec == null) continue;
      anySpec = true;
      final f = _mapSpecToFormFields(spec);
      transmissions.add(sellFlowTransmissionLabel(f.transmission));
      fuelTypes.add(sellFlowFuelLabel(f.fuelType));
      bodyTypes.add(sellFlowBodyLabel(f.bodyType));
      driveTypes.add(sellFlowDriveLabel(f.driveType));
      if (f.cylinderCount != null && f.cylinderCount! > 0) {
        cylinderCounts.add('${f.cylinderCount}');
      }
      if (f.engineSizeLiters != null && f.engineSizeLiters! > 0) {
        engineSizes.add(f.engineSizeLiters!.toStringAsFixed(1));
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

  _Trim? _trimForModelYear(int datasetModelId, int year) {
    final rows = _trimsByModelId[datasetModelId] ?? [];
    for (final t in rows) {
      if (t.year == year) return t;
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
    try {
      return _mapSpecToFormFields(spec);
    } catch (e, st) {
      debugPrint('CarSpecIndex.appliedFieldsFor failed: $e\n$st');
      return null;
    }
  }

  static CatalogSpecFields _mapSpecToFormFields(_Spec s) {
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

    double? engineLiters;
    if (s.displacementCc != null && s.displacementCc! > 0) {
      engineLiters = s.displacementCc! / 1000.0;
    } else {
      engineLiters = _parseDisplacementLiters(raw['Displacement:']?.toString());
    }

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
      cylinderCount: cylinders,
      fuelEconomy: fuelEconomy,
      seating: seating,
    );
  }

  static String _normBrand(String s) => s.toLowerCase().trim();

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
  final int? cylinderCount;
  final String? fuelEconomy;
  final int? seating;
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
  _Trim({required this.id, required this.modelId, required this.year, required this.name});
  final int id;
  final int modelId;
  final int year;
  final String name;

  static _Trim fromJson(Map<String, dynamic> j) => _Trim(
        id: _jsonInt(j['id']),
        modelId: _jsonInt(j['model_id']),
        year: _jsonInt(j['year']),
        name: (j['name'] ?? '').toString(),
      );
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
