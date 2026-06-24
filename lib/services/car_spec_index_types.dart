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

/// Sell step 2 picker label for transmission (internal API value from [CatalogSpecFields]).
