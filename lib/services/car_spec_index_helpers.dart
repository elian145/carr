part of 'car_spec_index.dart';

mixin CarSpecIndexHelpers on CarSpecIndexBase {
  /// Every dataset row (model + trim) of the model line of [appModel], across
  /// ALL years. This is the one source of every specification option and every
  /// linked-spec relationship: BRAND + MODEL defines the options. Neither the
  /// selected year nor the selected trim narrows it (an approved IQ overlay only
  /// ever widens it, elsewhere).
  List<({_Model model, _Trim trim})> _modelLevelRows(
    int brandId,
    String appModel,
  ) {
    final out = <({_Model model, _Trim trim})>[];
    for (final m in _familyModels(brandId, appModel)) {
      for (final t in _trimsByModelId[m.id] ?? const <_Trim>[]) {
        out.add((model: m, trim: t));
      }
    }
    return out;
  }

  List<({int datasetModelId, CatalogSpecFields fields, OnlineSpecVariant variant})>
      _catalogSellRowsDeduped(
    int brandId,
    String appModel,
    int? preferYear,
  ) {
    final out =
        <({int datasetModelId, CatalogSpecFields fields, OnlineSpecVariant variant})>[];
    final seen = <String>{};
    var scoped = _modelLevelRows(brandId, appModel);
    if (preferYear != null) {
      // Only used to choose the DEFAULT row an explicit "Apply specs" pre-fills
      // (never to filter options): rows of that model year first, else all.
      final inYear =
          scoped.where((r) => r.trim.coversYear(preferYear)).toList();
      if (inYear.isNotEmpty) scoped = inYear;
    }
    for (final row in scoped) {
      final m = row.model;
      final trim = row.trim;
      final spec = _specForTrim(trim.id);
      if (spec == null) continue;
      final CatalogSpecFields f;
      try {
        f = _formFieldsForTrim(m, trim, spec);
      } catch (e, st) { logNonFatal(e, st); 
        continue;
      }
      final key = <String?>[
        f.engineSizeLiters?.toStringAsFixed(2),
        f.displacementSuffix,
        f.cylinderCount?.toString(),
        f.transmission,
        f.driveType,
        (f.bodyTypes.toList()..sort()).join('+'),
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

  /// The index is immutable once built, so family lookups are memoized: the
  /// year-window resolvers ask for the same family once per model year.
  final Map<String, List<_Model>> _familyModelsCache = <String, List<_Model>>{};

  List<_Model> _familyModels(int brandId, String appModel) {
    final fam = appModel.trim();
    if (fam.isEmpty) return const [];
    final famLower = fam.toLowerCase();
    final catalogModels = CarCatalog.models;
    return _familyModelsCache.putIfAbsent(
      '$brandId\x1e$famLower\x1e${identityHashCode(catalogModels)}',
      () {
        final list = _modelsByBrandId[brandId] ?? const <_Model>[];
        final brandName = _brandsById[brandId]?.name ?? '';
        // Sibling isolation: a row whose dataset name is also claimed by a
        // MORE SPECIFIC catalog model of the same brand ("Land Cruiser Prado
        // 2 7" for "Land Cruiser", "Golf R 2 0" for "Golf") belongs to that
        // longer model only. Longest canonical model wins, exactly like the
        // tooling's `ModelIndex.resolve`.
        final longer = _longerCatalogSiblings(catalogModels, brandName, fam);
        return List<_Model>.unmodifiable(
          list
              .where(
                (m) =>
                    carSpecDatasetNameMatchesFamily(brandName, fam, m.name) &&
                    !longer.any(
                      (x) => carSpecDatasetNameMatchesFamily(brandName, x, m.name),
                    ) &&
                    // Last step: reviewed qualifier exclusions (a different
                    // vehicle line that merely starts with this model name).
                    !carSpecDatasetNameIsReviewedExclusion(brandName, fam, m.name),
              )
              .toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            ),
        );
      },
    );
  }

  /// Catalog models per spaced brand key (rebuilt only when the catalog map
  /// instance changes). Source of the sibling boundaries.
  Map<String, List<String>>? _siblingModelsByBrandKey;
  Object? _siblingModelsSource;

  /// Catalog models of [brandName] that are whole-word extensions of [family]
  /// ("Land Cruiser Prado" for "Land Cruiser"), i.e. the only models that can
  /// own a row [family] would otherwise absorb. Empty when the catalog does
  /// not list the brand or the model has no longer sibling.
  List<String> _longerCatalogSiblings(
    Map<String, List<String>> catalogModels,
    String brandName,
    String family,
  ) {
    if (!identical(_siblingModelsSource, catalogModels)) {
      _siblingModelsSource = catalogModels;
      _siblingModelsByBrandKey = <String, List<String>>{
        for (final e in catalogModels.entries)
          carSpecSpacedNameKey(e.key): e.value,
      };
    }
    final models = _siblingModelsByBrandKey![carSpecSpacedNameKey(brandName)];
    if (models == null) return const <String>[];
    final famKey = carSpecSpacedNameKey(family);
    return <String>[
      for (final x in models)
        if (carSpecSpacedNameKey(x).startsWith('$famKey ')) x,
    ];
  }

  /// Memoized [_mapSpecToFormFields] for a dataset trim. The mapping depends
  /// only on the trim's spec and its `"<model> <trim>"` label, never on the
  /// model year, so a trim that spans many model years is mapped once instead
  /// of once per year. Throws are not cached (callers keep their own handling).
  final Map<int, CatalogSpecFields> _formFieldsByTrimIdCache =
      <int, CatalogSpecFields>{};

  CatalogSpecFields _formFieldsForTrim(_Model m, _Trim trim, _Spec spec) {
    final cached = _formFieldsByTrimIdCache[trim.id];
    if (cached != null) return cached;
    final f = _mapSpecToFormFields(
      spec,
      catalogLabelHint: '${m.name} ${trim.name}',
    );
    _formFieldsByTrimIdCache[trim.id] = f;
    return f;
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

  /// The row of [datasetModelId] whose explicit year range contains [year], or
  /// null. Only used for per-row facts (e.g. the default row of an explicit
  /// "Apply specs"), never to narrow option lists.
  _Trim? _strictTrimForModelYear(int datasetModelId, int year) {
    for (final t in _trimsByModelId[datasetModelId] ?? const <_Trim>[]) {
      if (t.coversYear(year)) return t;
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

    // Evidence only: blank / unknown / contradictory source text yields null
    // (see car_spec_index_body_drive.dart). Never a factual default.
    final String? driveType =
        carSpecDriveKey(s.drivetrain, raw['Traction:']?.toString());

    final bodyTypes = carSpecBodyKeys(s.bodyType);
    final String? bodyType = carSpecSingleBodyKey(bodyTypes);

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
      bodyTypes: bodyTypes,
      engineSizeLiters: engineLiters,
      displacementSuffix: displacementSuffix,
      cylinderCount: cylinders,
      fuelEconomy: fuelEconomy,
      seating: seating,
    );
  }

  /// Brand identity: case-insensitive, trimmed, with cosmetic `-`/`_` folded to
  /// a space so catalog `Rolls Royce` resolves dataset `Rolls-Royce`.
  String _normBrand(String s) => carSpecSpacedNameKey(s);

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

/// Lower-cases and folds the purely cosmetic separators `-` and `_` to a
/// single space (`"5-Series"` == `"5 Series"`, `"ATS-V"` == `"ATS V"`,
/// `"Rolls-Royce"` == `"Rolls Royce"`). Everything else is kept verbatim: no
/// other punctuation is stripped, so token/family identity is preserved (`/`
/// in particular is NOT folded: `"2500/3500"` stays one token).
String carSpecSpacedNameKey(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[-_]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Explicit, reviewed dataset-name prefixes for catalog families whose dataset
/// spelling cannot be bridged by [carSpecSpacedNameKey]. Keyed
/// `"<spaced brand>|<spaced model>"`; every prefix is matched as a whole
/// leading phrase. Deliberately tiny and exact (no fuzzy matching).
///
/// * Ram 2500: the dataset only has the combined `"2500/3500 2500 ..."` /
///   `"2500/3500 3500 ..."` rows. Only rows explicitly labelled `2500` belong to
///   the catalog's `2500` model; the `3500` rows stay unmatched.
const Map<String, List<String>> _reviewedDatasetFamilyPrefixes =
    <String, List<String>>{
  'ram|2500': <String>['2500/3500 2500'],
};

/// Reviewed qualifier exclusions: dataset-name prefixes that start with a
/// catalog model's name but identify a DIFFERENT vehicle line (or are a
/// model-number / displacement split), so the model must not absorb them.
/// Keyed `"<spaced brand>|<spaced model>"`; every entry is a spaced whole-phrase
/// prefix of the dataset name.
///
/// Source of truth: `recommendation.exclusion_entries` of
/// `tools/catalog_enrichment/iqcars/generated/iqcars_qualifier_quarantine_audit.json`
/// (18 entries, 572 dataset rows, 13 models). It is deliberately NOT the
/// tooling's whole `ambiguous_qualifier` quarantine: trims, engine designations,
/// series names and the still-ambiguous grades (S, R, V, E, K, M, N, DRW, ...)
/// keep matching. Never add an entry without an audit row behind it.
@visibleForTesting
const Map<String, List<String>> carSpecReviewedFamilyExclusions =
    <String, List<String>>{
  'ford|transit': <String>['transit connect'],
  'gmc|sierra': <String>['sierra 2500hd', 'sierra 3500hd'],
  'suzuki|sx4': <String>['sx4 s cross'],
  'suzuki|vitara': <String>['vitara brezza', 'vitara e vitara'],
  'toyota|crown': <String>['crown majesta'],
  'toyota|corolla': <String>['corolla verso', 'corolla spacio', 'corolla rumion'],
  'toyota|avensis': <String>['avensis verso'],
  'toyota|urban cruiser': <String>['urban cruiser hyryder'],
  'volkswagen|polo': <String>['polo vivo'],
  'mercedes benz|eqs': <String>['eqs suv'],
  'renault|megane': <String>['megane grandcoupe'],
  'hyundai|ioniq': <String>['ioniq 9'],
  'chery|tiggo 2': <String>['tiggo 2 0', 'tiggo 2 4'],
};

/// True when [datasetName] is one of the reviewed exclusions of the catalog
/// model [familyName] of brand [brandName] (model-specific: an entry never
/// applies to another brand or model). Visible for tests; the production caller
/// is `CarSpecIndex._familyModels`.
@visibleForTesting
bool carSpecDatasetNameIsReviewedExclusion(
  String brandName,
  String familyName,
  String datasetName,
) {
  final prefixes = carSpecReviewedFamilyExclusions[
      '${carSpecSpacedNameKey(brandName)}|${carSpecSpacedNameKey(familyName)}'];
  if (prefixes == null) return false;
  final dn = carSpecSpacedNameKey(datasetName);
  for (final p in prefixes) {
    if (dn == p || dn.startsWith('$p ')) return true;
  }
  return false;
}

/// True when the dataset model [datasetName] belongs to the app catalog model
/// line [familyName] of brand [brandName].
///
/// Three additive rules, nothing fuzzy:
/// 1. legacy: equality, `"<family> ..."` prefix, or first token == family
///    (multi-word `"5 Series 540i"` and single-word `"Sportage 2 0 ..."`);
/// 2. the same equality / whole-word prefix on [carSpecSpacedNameKey] forms, so
///    hyphen/underscore vs space spelling (`5-Series` / `5 Series`) bridges;
/// 3. a reviewed explicit prefix alias (see [_reviewedDatasetFamilyPrefixes]).
///
/// Visible for tests; the production caller is `CarSpecIndex._familyModels`.
@visibleForTesting
bool carSpecDatasetNameMatchesFamily(
  String brandName,
  String familyName,
  String datasetName,
) {
  final famLower = familyName.trim().toLowerCase();
  if (famLower.isEmpty) return false;
  final dn = datasetName.trim().toLowerCase();
  if (dn.isEmpty) return false;
  if (dn == famLower || dn.startsWith('$famLower ')) return true;
  if (dn.split(RegExp(r'\s+')).first == famLower) return true;
  final famKey = carSpecSpacedNameKey(famLower);
  final dnKey = carSpecSpacedNameKey(dn);
  if (dnKey == famKey || dnKey.startsWith('$famKey ')) return true;
  final aliases =
      _reviewedDatasetFamilyPrefixes['${carSpecSpacedNameKey(brandName)}|$famKey'];
  if (aliases == null) return false;
  final flat = dn.replaceAll(RegExp(r'\s+'), ' ');
  for (final p in aliases) {
    if (flat == p || flat.startsWith('$p ')) return true;
  }
  return false;
}