part of 'car_spec_index.dart';

mixin CarSpecIndexCatalog on CarSpecIndexHelpers {
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
}
