part of 'car_spec_index.dart';

mixin CarSpecIndexCatalog on CarSpecIndexHelpers {
  int? datasetBrandId(String appBrand) {
    final key = _normBrand(appBrand);
    for (final b in _brandsById.values) {
      if (_normBrand(b.name) == key) return b.id;
    }
    return null;
  }

  /// Dataset model names the family of [appModel] resolves to (audit/tests).
  @visibleForTesting
  List<String> debugFamilyDatasetModelNames(String appBrand, String appModel) {
    final bid = datasetBrandId(appBrand);
    if (bid == null) return const <String>[];
    return [for (final m in _familyModels(bid, appModel)) m.name];
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
  ///
  /// This is the list of SELECTABLE model years only (the explicit year ranges of
  /// the dataset rows plus the recent-years tail). It is independent of the
  /// specification options: a year never disappears because a spec row for that
  /// exact year is missing, and a year never changes any option list.
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

  /// Distinct equipment rows of the whole model line (brand + model), deduped and
  /// sorted by engine size. [appTrim] and [year] are accepted for call-site
  /// compatibility and have NO effect: specification options are model-level.
  List<OnlineSpecVariant> catalogSellSpecVariants(
    String appBrand,
    String appModel, [
    String appTrim = CarSpecIndexBase.catalogAutofillModelOnly,
    int? year,
  ]) {
    final bid = datasetBrandId(appBrand);
    if (bid == null) return const [];
    final rows = _catalogSellRowsDeduped(bid, appModel, null);
    if (rows.isEmpty) return const [];
    _sortCatalogSellRows(rows);
    return rows.map((e) => e.variant).toList();
  }

  /// Default row for an explicit catalog "Apply specs" for [year]: the first
  /// [catalogSellSpecVariants] entry among the rows that cover that model year,
  /// or among all model rows when none does. It only picks the PRE-FILLED
  /// default; it never narrows the available options.
  CatalogSellRepresentative? representativeForCatalogSell(
    String appBrand,
    String appModel,
    String appTrim,
    int year,
  ) {
    final bid = datasetBrandId(appBrand);
    if (bid == null) return null;
    final rows = _catalogSellRowsDeduped(bid, appModel, year);
    if (rows.isEmpty) return null;
    _sortCatalogSellRows(rows);
    final r = rows.first;
    return CatalogSellRepresentative(
      datasetModelId: r.datasetModelId,
      fields: r.fields,
    );
  }
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

  /// True if [year] is inside the explicit year range of this dataset row.
  bool datasetVariantCoversYear(int datasetModelId, int year) {
    return _strictTrimForModelYear(datasetModelId, year) != null;
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

  /// Union of sell-step values for EVERY catalog row of the model line (brand +
  /// model, all years). The model alone defines these option lists: [year] and
  /// [appTrim] are accepted for call-site compatibility and have NO effect (the
  /// dataset rows AND the model-level IQ additions are the same for every trim).
  /// Null when there is no coverage or no spec rows.
  CatalogSellFieldOptions? sellFieldOptionsUnion(
    String appBrand,
    String appModel,
    String appTrim, [
    int? year,
  ]) {
    final bid = datasetBrandId(appBrand);
    if (bid == null) return iqOnlyFieldOptions(appBrand, appModel, appTrim);
    final family = _familyModels(bid, appModel);
    if (family.isEmpty) return iqOnlyFieldOptions(appBrand, appModel, appTrim);
    final scoped = _modelLevelRows(bid, appModel);
    if (scoped.isEmpty) return null;

    final transmissions = <String>{};
    final fuelTypes = <String>{};
    final bodyTypes = <String>{};
    final driveTypes = <String>{};
    final cylinderCounts = <String>{};
    final engineSizes = <String>{};
    final seatings = <String>{};

    var anySpec = false;
    for (final row in scoped) {
      final m = row.model;
      final trim = row.trim;
      final spec = _specForTrim(trim.id);
      if (spec == null) continue;
      anySpec = true;
      final f = _formFieldsForTrim(m, trim, spec);
      transmissions.add(sellFlowTransmissionLabel(f.transmission));
      fuelTypes.add(sellFlowFuelLabel(f.fuelType));
      // Evidence only: a row without a recognised body / drivetrain adds nothing.
      for (final k in f.bodyTypes) {
        final label = sellFlowBodyLabel(k);
        if (label != null) bodyTypes.add(label);
      }
      final driveLabel = sellFlowDriveLabel(f.driveType);
      if (driveLabel != null) driveTypes.add(driveLabel);
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
    // Approved IQ Cars additions (additive, model-level, whatever the trim is).
    // They are a plain UNION of option labels; IQ publishes no trim / engine /
    // cylinder / fuel relationship, so none is ever derived from them (linked
    // selection stays in the trusted reconcilers). It also fills an empty CarNet
    // set (no "baseline must be non-empty" rule).
    _iqOverlay.addEngineSizes(engineSizes, appBrand, appModel);
    _iqOverlay.addCylinderCounts(cylinderCounts, appBrand, appModel);
    final iqCylinders = _iqOverlay.approvedCylinderLabels(appBrand, appModel);
    return CatalogSellFieldOptions(
      transmissions: transmissions,
      fuelTypes: fuelTypes,
      bodyTypes: bodyTypes,
      driveTypes: driveTypes,
      cylinderCounts: cylinderCounts,
      engineSizes: engineSizes,
      seatings: seatings,
      iqCylinderCounts: iqCylinders,
    );
  }

  /// Field-aware coverage for a model the spec dataset has NO rows for
  /// ([hasCoverage] is false). The approved IQ overlay counts as coverage for
  /// the specific field it provides and for nothing else:
  ///
  /// * engine sizes -> only if IQ approved engine sizes for this Brand + Model;
  /// * cylinder counts -> only if IQ approved cylinder counts;
  /// * every other field stays empty, so callers keep their defaults for it.
  ///
  /// Returns null (callers keep their existing fallback, exactly as before)
  /// when IQ has neither. A selected trim never changes the result: the lists are
  /// model-level.
  CatalogSellFieldOptions? iqOnlyFieldOptions(
    String appBrand,
    String appModel,
    String appTrim,
  ) {
    final overlay = _iqOverlay;
    final hasEngines = overlay.hasEngineSizes(appBrand, appModel);
    final hasCylinders = overlay.hasCylinderCounts(appBrand, appModel);
    if (!hasEngines && !hasCylinders) return null;
    final engineSizes = <String>{};
    final cylinderCounts = <String>{};
    overlay.addEngineSizes(engineSizes, appBrand, appModel);
    overlay.addCylinderCounts(cylinderCounts, appBrand, appModel);
    if (engineSizes.isEmpty && cylinderCounts.isEmpty) return null;
    return CatalogSellFieldOptions(
      transmissions: <String>{},
      fuelTypes: <String>{},
      bodyTypes: <String>{},
      driveTypes: <String>{},
      cylinderCounts: cylinderCounts,
      engineSizes: engineSizes,
      seatings: <String>{},
      iqCylinderCounts: Set<String>.of(cylinderCounts),
    );
  }

  /// Approved IQ Cars additions merged into [sellFieldOptionsUnion] (and thus
  /// every Search / Sell engine-size and cylinder option set). [IqCarsOverlay.empty]
  /// until [CarSpecIndexHomeFilter.attachIqCarsOverlay] is called.
  IqCarsOverlay _iqOverlay = IqCarsOverlay.empty;

  /// The attached overlay (read-only), mainly for tests and diagnostics.
  IqCarsOverlay get iqCarsOverlay => _iqOverlay;

  List<String>? _allCatalogEngineSizeLabelsCache;

  /// The cached [allCatalogEngineSizeLabels] if it has been built, else null.
  /// Never scans the catalog.
  List<String>? peekAllCatalogEngineSizeLabels() =>
      _allCatalogEngineSizeLabelsCache;

  Map<int, String> _trimHintsById() {
    final trimHintById = <int, String>{};
    for (final entry in _trimsByModelId.entries) {
      final model = _modelsById[entry.key];
      for (final trim in entry.value) {
        trimHintById[trim.id] =
            model != null ? '${model.name} ${trim.name}' : trim.name;
      }
    }
    return trimHintById;
  }

  void _collectEngineLabels(
    Iterable<MapEntry<int, _Spec>> specs,
    Map<int, String> trimHintById,
    Set<String> out,
  ) {
    for (final entry in specs) {
      try {
        final fields = _mapSpecToFormFields(
          entry.value,
          catalogLabelHint: trimHintById[entry.key],
        );
        final liters = fields.engineSizeLiters;
        if (liters == null || liters <= 0.001) continue;
        out.add('${liters.toStringAsFixed(1)}${fields.displacementSuffix}');
      } catch (_) {
        // Skip malformed rows; still return the rest of the catalog.
      }
    }
  }

  List<String> _sortedEngineLabels(Set<String> engines) {
    return engines.toList()
      ..sort((a, b) {
        final ae = OnlineSpecVariant.parseLeadingEngineLiters(a) ?? 0;
        final be = OnlineSpecVariant.parseLeadingEngineLiters(b) ?? 0;
        final c = ae.compareTo(be);
        if (c != 0) return c;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
  }

  /// Every distinct engine-size label in the bundled catalog (e.g. `2.0`, `2.0 T`,
  /// `3.0 D`), sorted by liters then label. Cached after first call.
  ///
  /// This maps every spec row, so a cold call is expensive; UI paths that must
  /// stay responsive should use [peekAllCatalogEngineSizeLabels] and let
  /// [prewarmAllCatalogEngineSizeLabels] fill the cache in the background.
  List<String> allCatalogEngineSizeLabels() {
    final cached = _allCatalogEngineSizeLabelsCache;
    if (cached != null) return cached;
    final engines = <String>{};
    _collectEngineLabels(_specByTrimId.entries, _trimHintsById(), engines);
    return _allCatalogEngineSizeLabelsCache = _sortedEngineLabels(engines);
  }

  /// Builds the same cache as [allCatalogEngineSizeLabels] in short time slices
  /// (about [sliceBudget] each), waiting for the next frame between slices so
  /// the scan never holds the UI isolate for a whole frame. Safe to call
  /// repeatedly / alongside the sync getter (both yield the identical list).
  Future<void> prewarmAllCatalogEngineSizeLabels({
    Duration sliceBudget = const Duration(milliseconds: 3),
  }) async {
    if (_allCatalogEngineSizeLabelsCache != null) return;
    final hints = _trimHintsById();
    final engines = <String>{};
    final entries = _specByTrimId.entries.toList(growable: false);
    const batch = 16;
    var i = 0;
    while (i < entries.length) {
      if (_allCatalogEngineSizeLabelsCache != null) return;
      final slice = Stopwatch()..start();
      do {
        final end = i + batch < entries.length ? i + batch : entries.length;
        _collectEngineLabels(entries.getRange(i, end), hints, engines);
        i = end;
      } while (i < entries.length && slice.elapsed < sliceBudget);
      if (i < entries.length) await _yieldToNextFrame();
    }
    _allCatalogEngineSizeLabelsCache ??= _sortedEngineLabels(engines);
  }

  static Future<void> _yieldToNextFrame() {
    try {
      return SchedulerBinding.instance.endOfFrame;
    } catch (_) {
      // No Flutter binding (plain Dart test): fall back to the event loop.
      return Future<void>.delayed(Duration.zero);
    }
  }
}