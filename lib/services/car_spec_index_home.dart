part of 'car_spec_index.dart';

mixin CarSpecIndexHomeFilter on CarSpecIndexCatalog {
  /// Union of **every** catalog-derived Sell field ([sellFieldOptionsUnion] — the
  /// exact resolver Sell step 2 uses) across the catalog years in scope for the
  /// home/search filters.
  ///
  /// With no year bounds all catalog years for the make/model(/trim) are unioned;
  /// with [rangeMinYear]/[rangeMaxYear] only the years inside that window are.
  /// Each field set is independent: an empty set means "the catalog has no data
  /// for this field" (callers fall back to defaults for that field only).
  ///
  /// Returns null when the catalog cannot answer at all (unknown brand/model, no
  /// spec rows, or the year window excludes every catalog year).
  CatalogSellFieldOptions? homeFilterFieldOptions(
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
    if (yearList.isEmpty) return null;
    final transmissions = <String>{};
    final fuelTypes = <String>{};
    final bodyTypes = <String>{};
    final driveTypes = <String>{};
    final cylinderCounts = <String>{};
    final engineSizes = <String>{};
    final seatings = <String>{};
    var anyRow = false;
    for (final y in yearList) {
      final o = sellFieldOptionsUnion(appBrand, appModel, appTrim, y);
      if (o == null) continue;
      anyRow = true;
      transmissions.addAll(o.transmissions);
      fuelTypes.addAll(o.fuelTypes);
      bodyTypes.addAll(o.bodyTypes);
      driveTypes.addAll(o.driveTypes);
      cylinderCounts.addAll(o.cylinderCounts);
      engineSizes.addAll(o.engineSizes);
      seatings.addAll(o.seatings);
    }
    if (!anyRow) return null;
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

  /// Deduped [OnlineSpecVariant] rows across all catalog years in scope for home filters
  /// (same year window as [homeFilterFieldOptions]).
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
      appLog('CarSpecIndex.appliedFieldsFor failed: $e\n$st');
      return null;
    }
  }

}
