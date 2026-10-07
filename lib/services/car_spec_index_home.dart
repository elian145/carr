part of 'car_spec_index.dart';

mixin CarSpecIndexHomeFilter on CarSpecIndexCatalog {
  /// Union of **every** catalog-derived Sell field ([sellFieldOptionsUnion], the
  /// exact resolver Sell step 2 uses) for the make + model.
  ///
  /// BRAND + MODEL ONLY defines these options. [rangeMinYear] / [rangeMaxYear] are
  /// accepted for call-site compatibility and have NO effect: a Search year or
  /// year range only filters the listings, never the specification options.
  /// Each field set is independent: an empty set means "the catalog has no data
  /// for this field" (callers fall back to defaults for that field only).
  ///
  /// Returns null when the catalog cannot answer at all (unknown brand/model or
  /// no spec rows).
  CatalogSellFieldOptions? homeFilterFieldOptions(
    String appBrand,
    String appModel,
    String appTrim, {
    int? rangeMinYear,
    int? rangeMaxYear,
  }) {
    // The index is immutable, so the answer for one vehicle never changes:
    // re-selecting a model (or flipping between two) is then free.
    // Keyed by brand + model only: [appTrim] never changes the options.
    final cacheKey = '$appBrand\x1e$appModel';
    if (_homeFilterFieldOptionsCache.containsKey(cacheKey)) {
      return _homeFilterFieldOptionsCache[cacheKey];
    }
    final resolved = _resolveHomeFilterFieldOptions(appBrand, appModel, appTrim);
    _homeFilterFieldOptionsCache[cacheKey] = resolved;
    return resolved;
  }
  final Map<String, CatalogSellFieldOptions?> _homeFilterFieldOptionsCache =
      <String, CatalogSellFieldOptions?>{};

  /// Attaches the approved IQ Cars additions. Memoised resolutions made before
  /// the overlay arrived are dropped so they are recomputed once with it.
  /// Passing null / [IqCarsOverlay.empty] restores the pure catalog behaviour.
  void attachIqCarsOverlay(IqCarsOverlay? overlay) {
    final next = overlay ?? IqCarsOverlay.empty;
    if (identical(next, _iqOverlay)) return;
    _iqOverlay = next;
    _homeFilterFieldOptionsCache.clear();
  }

  CatalogSellFieldOptions? _resolveHomeFilterFieldOptions(
    String appBrand,
    String appModel,
    String appTrim,
  ) {
    // Legacy gate: the spec dataset must know the model line. A model it does
    // not know can still be answered, field by field, by the approved IQ
    // overlay (model-level, independent of year and trim).
    if (!hasCoverage(appBrand, appModel)) {
      return iqOnlyFieldOptions(appBrand, appModel, appTrim);
    }
    // Brand + model defines the options: ONE model-level union, regardless of
    // any selected year or year range (those only filter listings).
    return sellFieldOptionsUnion(appBrand, appModel, appTrim);
  }

  /// Deduped [OnlineSpecVariant] rows of the whole model line (brand + model),
  /// the relationship evidence for Search's linked engine / cylinders / fuel.
  /// [rangeMinYear] / [rangeMaxYear] are accepted for call-site compatibility
  /// and have NO effect: the model defines the rows, the year range only filters
  /// listings.
  List<OnlineSpecVariant> homeFilterSpecVariantsUnion(
    String appBrand,
    String appModel,
    String appTrim, {
    int? rangeMinYear,
    int? rangeMaxYear,
  }) {
    if (!hasCoverage(appBrand, appModel)) return const [];
    final seen = <String>{};
    final out = <OnlineSpecVariant>[];
    for (final v in catalogSellSpecVariants(appBrand, appModel, appTrim)) {
      if (seen.add(_homeFilterVariantDedupeKey(v))) out.add(v);
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

  CatalogSpecFields? appliedFieldsFor(int datasetModelId, int year) {
    final trim = _strictTrimForModelYear(datasetModelId, year);
    if (trim == null) return null;
    final spec = _specForTrim(trim.id);
    if (spec == null) return null;
    final model = _modelsById[datasetModelId];
    final hint =
        model != null ? '${model.name} ${trim.name}' : trim.name;
    try {
      return _mapSpecToFormFields(spec, catalogLabelHint: hint);
    } catch (e, st) {
      appLog('CarSpecIndex.appliedFieldsFor failed: $e\n$st');
      return null;
    }
  }

}
