part of 'car_spec_index.dart';

mixin CarSpecIndexHomeFilter on CarSpecIndexCatalog {
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
