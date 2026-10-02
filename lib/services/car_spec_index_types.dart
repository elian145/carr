part of 'car_spec_index.dart';

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

/// Shared "catalog narrows, defaults fall back" contract used by **both** Sell
/// step 2 and Search/Filters for every catalog-dependent field.
///
/// * [known] has values  -> only the entries of [defaults] that the catalog knows
///   (default list order/labels are preserved). [passthrough] (the filter-only
///   `Any` entry) is always kept in place.
/// * [known] is null/empty (catalog has no data for this field), or none of the
///   known values exist in [defaults] -> the full [defaults] list. A missing field
///   must never produce an empty picker, and values are never inferred.
List<String> narrowOptionsToCatalog(
  List<String> defaults,
  Set<String>? known, {
  String passthrough = 'Any',
}) {
  if (known == null || known.isEmpty) return defaults;
  final narrowed = defaults
      .where((e) => e == passthrough || known.contains(e))
      .toList(growable: false);
  final hasRealOption = narrowed.any((e) => e != passthrough);
  return hasRealOption ? narrowed : defaults;
}

/// Engine-size labels (`2.0`, `3.5 T`, ...) ordered by litres, then label.
/// Shared by Sell step 2 and Search so both list catalog engines identically.
List<String> sortCatalogEngineSizeLabels(Iterable<String> labels) {
  final sorted = labels.toList()
    ..sort((a, b) {
      final ae = OnlineSpecVariant.parseLeadingEngineLiters(a) ?? 0;
      final be = OnlineSpecVariant.parseLeadingEngineLiters(b) ?? 0;
      final c = ae.compareTo(be);
      if (c != 0) return c;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
  return sorted;
}

/// Sell step 2 picker label for transmission (internal API value from [CatalogSpecFields]).
