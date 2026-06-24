part of 'car_spec_index.dart';

int _jsonInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.parse(v.toString());
}

int? _jsonIntOpt(dynamic v) {
  if (v == null) return null;
  try {
    return _jsonInt(v);
  } catch (e, st) { logNonFatal(e, st); 
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
        appLog('CarSpecIndex: skip brand row: $err\n$st');
      }
    }

    final models = <_Model>[];
    for (final e in map['models'] as List<dynamic>? ?? const []) {
      if (e is! Map<String, dynamic>) continue;
      try {
        models.add(_Model.fromJson(e));
      } catch (err, st) {
        appLog('CarSpecIndex: skip model row: $err\n$st');
      }
    }

    final trims = <_Trim>[];
    for (final e in map['trims'] as List<dynamic>? ?? const []) {
      if (e is! Map<String, dynamic>) continue;
      try {
        trims.add(_Trim.fromJson(e));
      } catch (err, st) {
        appLog('CarSpecIndex: skip trim row: $err\n$st');
      }
    }

    final specByTrimId = <int, _Spec>{};
    for (final e in map['specs'] as List<dynamic>? ?? const []) {
      if (e is! Map<String, dynamic>) continue;
      try {
        final s = _Spec.fromJson(e);
        specByTrimId[s.trimId] = s;
      } catch (err, st) {
        appLog('CarSpecIndex: skip spec row: $err\n$st');
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
    appLog('CarSpecIndex parse failed: $e\n$st');
    return CarSpecIndexLoadResult._(
      errorMessage:
          'Could not parse spec database ($e). Ensure assets/car_spec_dataset.json is valid JSON.',
    );
  }
}

/// Parsed automobile-catalog style dataset (brands → models → trims by year → specs).
