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
    this.bodyTypes = const <String>{},
    this.engineSizeLiters,
    this.displacementSuffix = '',
    this.cylinderCount,
    this.fuelEconomy,
    this.seating,
  });

  final String engineType;
  final String fuelType;
  final String transmission;
  /// `fwd` / `rwd` / `awd`, or null when the source gave no (or contradictory)
  /// evidence. Never defaulted.
  final String? driveType;

  /// The row's body key when it has exactly one (form serialization only), else
  /// null. Never defaulted; see [bodyTypes] for every recognised category.
  final String? bodyType;

  /// Every body category explicitly recognised in the row's raw body value
  /// (empty when the source is blank / unknown). Drives Search/Sell options.
  final Set<String> bodyTypes;
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
    this.iqCylinderCounts = const <String>{},
  });

  /// The subset of [cylinderCounts] that came from the approved IQ Cars overlay
  /// (explicitly supplied model-level counts). Only these may be offered by a
  /// picker whose generic default range does not contain them (e.g. Sell's 3-12).
  final Set<String> iqCylinderCounts;

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

/// [narrowOptionsToCatalog] for cylinder counts, plus one extra rule: counts
/// that the approved IQ overlay explicitly supplied ([iqApproved], a subset of
/// [known]) are offered even when the picker's generic [defaults] range does
/// not contain them (Sell's 3-12 ladder vs. an IQ count of 1, 2 or 16).
///
/// Nothing else widens: counts from any other source that are outside
/// [defaults] are still dropped, the defaults are never expanded, and nothing
/// is inferred. With no IQ extras this is exactly [narrowOptionsToCatalog].
List<String> narrowCylinderOptionsToCatalog(
  List<String> defaults,
  Set<String>? known,
  Set<String>? iqApproved, {
  String passthrough = 'Any',
}) {
  if (known == null ||
      known.isEmpty ||
      iqApproved == null ||
      iqApproved.isEmpty) {
    return narrowOptionsToCatalog(defaults, known, passthrough: passthrough);
  }
  final extras = <String>{
    for (final c in iqApproved)
      if (known.contains(c) && !defaults.contains(c)) c,
  };
  if (extras.isEmpty) {
    return narrowOptionsToCatalog(defaults, known, passthrough: passthrough);
  }
  final merged = <String>[
    ...defaults.where((e) => e != passthrough && known.contains(e)),
    ...extras,
  ]..sort((a, b) {
      final ai = int.tryParse(a) ?? 1 << 30;
      final bi = int.tryParse(b) ?? 1 << 30;
      return ai != bi ? ai.compareTo(bi) : a.compareTo(b);
    });
  return <String>[
    if (defaults.contains(passthrough)) passthrough,
    ...merged,
  ];
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
