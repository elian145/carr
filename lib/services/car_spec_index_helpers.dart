part of 'car_spec_index.dart';

mixin CarSpecIndexHelpers on CarSpecIndexBase {
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
      } catch (e, st) { logNonFatal(e, st); 
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
  bool _datasetNameMatchesAppFamily(
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
  double trimMatchScore(String datasetVariantName, String appTrim) {
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
  CatalogSpecFields _mapSpecToFormFields(
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

  String _normBrand(String s) => s.toLowerCase().trim();

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
