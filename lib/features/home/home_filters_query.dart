import 'home_multi_select_filter.dart';
import '../../shared/i18n/region_spec_labels.dart';

/// Immutable home filter selection used for API queries and saved searches.
class HomeFiltersSnapshot {
  const HomeFiltersSnapshot({
    this.brand,
    this.model,
    this.trim,
    this.minPrice,
    this.maxPrice,
    this.minYear,
    this.maxYear,
    this.minMileage,
    this.maxMileage,
    this.condition,
    this.transmission,
    this.fuelType,
    this.bodyType,
    this.color,
    this.driveType,
    this.regionSpecs,
    this.cylinderCount,
    this.seating,
    this.engineSize,
    this.city,
    this.plateType,
    this.plateCity,
    this.titleStatus,
    this.damagedParts,
    this.sortByUi,
  });

  final String? brand;
  final String? model;
  final String? trim;
  final String? minPrice;
  final String? maxPrice;
  final String? minYear;
  final String? maxYear;
  final String? minMileage;
  final String? maxMileage;
  final String? condition;
  final String? transmission;
  final String? fuelType;
  final String? bodyType;
  final String? color;
  final String? driveType;
  final String? regionSpecs;
  final String? cylinderCount;
  final String? seating;
  final String? engineSize;
  final String? city;
  final String? plateType;
  final String? plateCity;
  final String? titleStatus;
  final String? damagedParts;
  final String? sortByUi;

  static bool _has(String? v) => v != null && v.isNotEmpty;

  static bool _isAny(String? v) =>
      v == null || v.isEmpty || v.toLowerCase() == 'any';

  bool get hasActiveFilters =>
      _has(brand) ||
      _has(model) ||
      _has(trim) ||
      _has(minPrice) ||
      _has(maxPrice) ||
      _has(minYear) ||
      _has(maxYear) ||
      _has(minMileage) ||
      _has(maxMileage) ||
      _has(condition) ||
      _has(transmission) ||
      _has(fuelType) ||
      _has(bodyType) ||
      _has(color) ||
      _has(driveType) ||
      _has(regionSpecs) ||
      _has(cylinderCount) ||
      _has(seating) ||
      _has(engineSize) ||
      _has(city) ||
      _has(plateType) ||
      _has(plateCity) ||
      _has(titleStatus) ||
      _has(damagedParts) ||
      _has(sortByUi);

  HomeFiltersSnapshot copyWith({
    String? brand,
    String? model,
    String? trim,
    String? minPrice,
    String? maxPrice,
    String? minYear,
    String? maxYear,
    String? minMileage,
    String? maxMileage,
    String? condition,
    String? transmission,
    String? fuelType,
    String? bodyType,
    String? color,
    String? driveType,
    String? regionSpecs,
    String? cylinderCount,
    String? seating,
    String? engineSize,
    String? city,
    String? plateType,
    String? plateCity,
    String? titleStatus,
    String? damagedParts,
    String? sortByUi,
    bool clearBrand = false,
    bool clearModel = false,
    bool clearTrim = false,
    bool clearMinPrice = false,
    bool clearMaxPrice = false,
    bool clearMinYear = false,
    bool clearMaxYear = false,
    bool clearMinMileage = false,
    bool clearMaxMileage = false,
    bool clearCondition = false,
    bool clearTransmission = false,
    bool clearFuelType = false,
    bool clearBodyType = false,
    bool clearColor = false,
    bool clearDriveType = false,
    bool clearRegionSpecs = false,
    bool clearCylinderCount = false,
    bool clearSeating = false,
    bool clearEngineSize = false,
    bool clearCity = false,
    bool clearPlateType = false,
    bool clearPlateCity = false,
    bool clearTitleStatus = false,
    bool clearDamagedParts = false,
    bool clearSortByUi = false,
  }) {
    return HomeFiltersSnapshot(
      brand: clearBrand ? null : (brand ?? this.brand),
      model: clearModel ? null : (model ?? this.model),
      trim: clearTrim ? null : (trim ?? this.trim),
      minPrice: clearMinPrice ? null : (minPrice ?? this.minPrice),
      maxPrice: clearMaxPrice ? null : (maxPrice ?? this.maxPrice),
      minYear: clearMinYear ? null : (minYear ?? this.minYear),
      maxYear: clearMaxYear ? null : (maxYear ?? this.maxYear),
      minMileage: clearMinMileage ? null : (minMileage ?? this.minMileage),
      maxMileage: clearMaxMileage ? null : (maxMileage ?? this.maxMileage),
      condition: clearCondition ? null : (condition ?? this.condition),
      transmission:
          clearTransmission ? null : (transmission ?? this.transmission),
      fuelType: clearFuelType ? null : (fuelType ?? this.fuelType),
      bodyType: clearBodyType ? null : (bodyType ?? this.bodyType),
      color: clearColor ? null : (color ?? this.color),
      driveType: clearDriveType ? null : (driveType ?? this.driveType),
      regionSpecs: clearRegionSpecs ? null : (regionSpecs ?? this.regionSpecs),
      cylinderCount:
          clearCylinderCount ? null : (cylinderCount ?? this.cylinderCount),
      seating: clearSeating ? null : (seating ?? this.seating),
      engineSize: clearEngineSize ? null : (engineSize ?? this.engineSize),
      city: clearCity ? null : (city ?? this.city),
      plateType: clearPlateType ? null : (plateType ?? this.plateType),
      plateCity: clearPlateCity ? null : (plateCity ?? this.plateCity),
      titleStatus: clearTitleStatus ? null : (titleStatus ?? this.titleStatus),
      damagedParts:
          clearDamagedParts ? null : (damagedParts ?? this.damagedParts),
      sortByUi: clearSortByUi ? null : (sortByUi ?? this.sortByUi),
    );
  }
}

/// Builds `/api/cars` query parameters from [filters].
Map<String, String> homeFiltersToApiQuery(
  HomeFiltersSnapshot filters, {
  String? apiSortValue,
  bool includeSort = true,
}) {
  final out = <String, String>{};

  void put(String key, String? value) {
    if (value != null && value.isNotEmpty) out[key] = value;
  }

  put('brand', filters.brand);
  put('model', filters.model);
  put('trim', filters.trim);
  put('min_price', filters.minPrice);
  put('max_price', filters.maxPrice);
  put('min_year', filters.minYear);
  put('max_year', filters.maxYear);
  put('min_mileage', filters.minMileage);
  put('max_mileage', filters.maxMileage);

  if (!HomeFiltersSnapshot._isAny(filters.condition)) {
    put('condition', filters.condition!.toLowerCase());
  }
  if (!HomeFiltersSnapshot._isAny(filters.transmission)) {
    put('transmission', filters.transmission!.toLowerCase());
  }
  if (!HomeFiltersSnapshot._isAny(filters.fuelType)) {
    put('fuel_type', filters.fuelType!.toLowerCase());
  }
  if (!HomeFiltersSnapshot._isAny(filters.bodyType)) {
    final bodyTypes = homeFilterDecodeList(filters.bodyType)
        .map((b) => b.toLowerCase())
        .toList();
    if (bodyTypes.isNotEmpty) {
      put('body_type', bodyTypes.join(homeFilterListSeparator));
    }
  }
  if (!HomeFiltersSnapshot._isAny(filters.color)) {
    put('color', filters.color!.toLowerCase());
  }
  if (!HomeFiltersSnapshot._isAny(filters.driveType)) {
    put('drive_type', filters.driveType!.toLowerCase());
  }
  if (HomeFiltersSnapshot._has(filters.regionSpecs) &&
      isValidCarRegionSpecCode(filters.regionSpecs)) {
    put('region_specs', filters.regionSpecs!.trim().toLowerCase());
  }
  if (!HomeFiltersSnapshot._isAny(filters.cylinderCount)) {
    put('cylinder_count', filters.cylinderCount);
  }
  if (!HomeFiltersSnapshot._isAny(filters.seating)) {
    put('seating', filters.seating);
  }
  if (!HomeFiltersSnapshot._isAny(filters.engineSize)) {
    put('engine_size', filters.engineSize);
  }

  put('city', filters.city);
  if (!HomeFiltersSnapshot._isAny(filters.plateType)) {
    put('plate_type', filters.plateType!.toLowerCase());
  }
  if (!HomeFiltersSnapshot._isAny(filters.plateCity)) {
    put('plate_city', filters.plateCity);
  }

  if (includeSort && apiSortValue != null && apiSortValue.isNotEmpty) {
    out['sort_by'] = apiSortValue;
  }

  if (HomeFiltersSnapshot._has(filters.titleStatus)) {
    out['title_status'] = filters.titleStatus!;
    if (filters.titleStatus == 'damaged' &&
        HomeFiltersSnapshot._has(filters.damagedParts)) {
      out['damaged_parts'] = filters.damagedParts!;
    }
  }

  return out;
}

/// Saved-search / server payload (matches [SavedSearchService.normalizeFilters] inputs).
Map<String, dynamic> homeFiltersToSavedSearchJson(
  HomeFiltersSnapshot filters, {
  String? apiSortValue,
}) {
  final out = <String, dynamic>{};

  void put(String key, String? value) {
    if (value != null && value.isNotEmpty) out[key] = value;
  }

  put('brand', filters.brand);
  put('model', filters.model);
  put('trim', filters.trim);
  put('min_price', filters.minPrice);
  put('max_price', filters.maxPrice);
  put('min_year', filters.minYear);
  put('max_year', filters.maxYear);
  put('min_mileage', filters.minMileage);
  put('max_mileage', filters.maxMileage);

  if (!HomeFiltersSnapshot._isAny(filters.condition)) {
    put('condition', filters.condition!.toLowerCase());
  }
  if (!HomeFiltersSnapshot._isAny(filters.transmission)) {
    put('transmission', filters.transmission!.toLowerCase());
  }
  if (!HomeFiltersSnapshot._isAny(filters.fuelType)) {
    put('fuel_type', filters.fuelType!.toLowerCase());
  }
  if (!HomeFiltersSnapshot._isAny(filters.bodyType)) {
    final bodyTypes = homeFilterDecodeList(filters.bodyType)
        .map((b) => b.toLowerCase())
        .toList();
    if (bodyTypes.isNotEmpty) {
      put('body_type', bodyTypes.join(homeFilterListSeparator));
    }
  }
  if (!HomeFiltersSnapshot._isAny(filters.color)) {
    put('color', filters.color!.toLowerCase());
  }
  if (!HomeFiltersSnapshot._isAny(filters.driveType)) {
    put('drive_type', filters.driveType!.toLowerCase());
  }
  if (HomeFiltersSnapshot._has(filters.regionSpecs) &&
      isValidCarRegionSpecCode(filters.regionSpecs)) {
    put('region_specs', filters.regionSpecs!.trim().toLowerCase());
  }
  if (!HomeFiltersSnapshot._isAny(filters.cylinderCount)) {
    put('cylinder_count', filters.cylinderCount);
  }
  if (!HomeFiltersSnapshot._isAny(filters.seating)) {
    put('seating', filters.seating);
  }

  put('city', filters.city);

  if (apiSortValue != null && apiSortValue.isNotEmpty) {
    out['sort_by'] = apiSortValue;
  }

  if (HomeFiltersSnapshot._has(filters.titleStatus)) {
    out['title_status'] = filters.titleStatus!;
    if (filters.titleStatus == 'damaged' &&
        HomeFiltersSnapshot._has(filters.damagedParts)) {
      out['damaged_parts'] = filters.damagedParts!;
    }
  }

  return out;
}

/// Client-side exact match when API returns broad damaged-title rows.
List<Map<String, dynamic>> applyDamagedPartsListingFilter(
  List<Map<String, dynamic>> source, {
  required String? selectedTitleStatus,
  required String? selectedDamagedParts,
}) {
  if (selectedTitleStatus != 'damaged') return source;
  if (selectedDamagedParts == null || selectedDamagedParts.isEmpty) {
    return source;
  }
  final targetParts = int.tryParse(selectedDamagedParts);
  if (targetParts == null) return source;

  return source.where((car) {
    final titleStatus = (car['title_status'] ?? car['titleStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (titleStatus != 'damaged') return false;
    final parts = int.tryParse(car['damaged_parts']?.toString() ?? '');
    return parts == targetParts;
  }).toList();
}
