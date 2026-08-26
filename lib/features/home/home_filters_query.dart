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

  put('brand', homeFilterDecodeSingle(filters.brand));
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
    final fuelTypes = homeFilterDecodeList(filters.fuelType)
        .map((f) => f.toLowerCase())
        .toList();
    if (fuelTypes.isNotEmpty) {
      put('fuel_type', fuelTypes.join(homeFilterListSeparator));
    }
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
    final driveTypes = homeFilterDecodeList(filters.driveType)
        .map((d) => d.toLowerCase())
        .toList();
    if (driveTypes.isNotEmpty) {
      put('drive_type', driveTypes.join(homeFilterListSeparator));
    }
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

  put('brand', homeFilterDecodeSingle(filters.brand));
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
    final fuelTypes = homeFilterDecodeList(filters.fuelType)
        .map((f) => f.toLowerCase())
        .toList();
    if (fuelTypes.isNotEmpty) {
      put('fuel_type', fuelTypes.join(homeFilterListSeparator));
    }
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
    final driveTypes = homeFilterDecodeList(filters.driveType)
        .map((d) => d.toLowerCase())
        .toList();
    if (driveTypes.isNotEmpty) {
      put('drive_type', driveTypes.join(homeFilterListSeparator));
    }
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

String? _listingStringField(Map<String, dynamic> listing, List<String> keys) {
  for (final key in keys) {
    final raw = listing[key];
    if (raw == null) continue;
    final value = raw.toString().trim();
    if (value.isNotEmpty) return value;
  }
  return null;
}

double? _listingNumField(Map<String, dynamic> listing, List<String> keys) {
  for (final key in keys) {
    final raw = listing[key];
    if (raw == null) continue;
    if (raw is num) return raw.toDouble();
    final parsed = double.tryParse(raw.toString().trim());
    if (parsed != null) return parsed;
  }
  return null;
}

bool _ciContains(String? haystack, String needle) {
  final h = haystack?.trim() ?? '';
  if (h.isEmpty) return false;
  return h.toLowerCase().contains(needle.trim().toLowerCase());
}

bool _ciEquals(String? left, String right) {
  final l = left?.trim() ?? '';
  if (l.isEmpty) return false;
  return l.toLowerCase() == right.trim().toLowerCase();
}

bool _matchesSelectedList(String? listingValue, String? encodedFilter) {
  final selected = homeFilterDecodeList(encodedFilter)
      .map((v) => v.toLowerCase())
      .toList();
  if (selected.isEmpty) return true;
  final value = listingValue?.trim().toLowerCase() ?? '';
  if (value.isEmpty) return false;
  return selected.contains(value);
}

bool _inNumericRange({
  required double? value,
  String? minRaw,
  String? maxRaw,
}) {
  final min = minRaw == null || minRaw.trim().isEmpty
      ? null
      : double.tryParse(minRaw.trim());
  final max = maxRaw == null || maxRaw.trim().isEmpty
      ? null
      : double.tryParse(maxRaw.trim());
  if (min == null && max == null) return true;
  if (value == null) return false;
  if (min != null && value < min) return false;
  if (max != null && value > max) return false;
  return true;
}

/// Whether [listing] matches [filters], using the same rules as `/api/cars`.
bool listingMatchesHomeFilters(
  Map<String, dynamic> listing,
  HomeFiltersSnapshot filters,
) {
  final brand = homeFilterDecodeSingle(filters.brand);
  if (HomeFiltersSnapshot._has(brand) &&
      !_ciContains(
        _listingStringField(listing, const ['brand']),
        brand!,
      )) {
    return false;
  }
  if (HomeFiltersSnapshot._has(filters.model) &&
      !_ciContains(
        _listingStringField(listing, const ['model']),
        filters.model!,
      )) {
    return false;
  }
  if (HomeFiltersSnapshot._has(filters.trim) &&
      !_ciContains(
        _listingStringField(listing, const ['trim']),
        filters.trim!,
      )) {
    return false;
  }
  if (!_inNumericRange(
    value: _listingNumField(listing, const ['price']),
    minRaw: filters.minPrice,
    maxRaw: filters.maxPrice,
  )) {
    return false;
  }
  if (!_inNumericRange(
    value: _listingNumField(listing, const ['year']),
    minRaw: filters.minYear,
    maxRaw: filters.maxYear,
  )) {
    return false;
  }
  if (!_inNumericRange(
    value: _listingNumField(listing, const ['mileage']),
    minRaw: filters.minMileage,
    maxRaw: filters.maxMileage,
  )) {
    return false;
  }
  if (!HomeFiltersSnapshot._isAny(filters.condition) &&
      !_ciEquals(
        _listingStringField(listing, const ['condition']),
        filters.condition!,
      )) {
    return false;
  }
  if (!HomeFiltersSnapshot._isAny(filters.transmission) &&
      !_ciEquals(
        _listingStringField(listing, const ['transmission']),
        filters.transmission!,
      )) {
    return false;
  }
  if (!HomeFiltersSnapshot._isAny(filters.fuelType) &&
      !_matchesSelectedList(
        _listingStringField(listing, const ['fuel_type', 'fuelType']),
        filters.fuelType,
      )) {
    return false;
  }
  if (!HomeFiltersSnapshot._isAny(filters.bodyType) &&
      !_matchesSelectedList(
        _listingStringField(listing, const ['body_type', 'bodyType']),
        filters.bodyType,
      )) {
    return false;
  }
  if (!HomeFiltersSnapshot._isAny(filters.color) &&
      !_ciContains(
        _listingStringField(listing, const ['color']),
        filters.color!,
      )) {
    return false;
  }
  if (!HomeFiltersSnapshot._isAny(filters.driveType) &&
      !_matchesSelectedList(
        _listingStringField(listing, const ['drive_type', 'driveType']),
        filters.driveType,
      )) {
    return false;
  }
  if (HomeFiltersSnapshot._has(filters.regionSpecs) &&
      isValidCarRegionSpecCode(filters.regionSpecs) &&
      !_ciEquals(
        _listingStringField(listing, const ['region_specs', 'regionSpecs']),
        filters.regionSpecs!,
      )) {
    return false;
  }
  if (!HomeFiltersSnapshot._isAny(filters.cylinderCount) &&
      !_inNumericRange(
        value: _listingNumField(
          listing,
          const ['cylinder_count', 'cylinderCount'],
        ),
        minRaw: filters.cylinderCount,
        maxRaw: filters.cylinderCount,
      )) {
    return false;
  }
  if (!HomeFiltersSnapshot._isAny(filters.seating) &&
      !_inNumericRange(
        value: _listingNumField(listing, const ['seating']),
        minRaw: filters.seating,
        maxRaw: filters.seating,
      )) {
    return false;
  }
  if (!HomeFiltersSnapshot._isAny(filters.engineSize) &&
      !_inNumericRange(
        value: _listingNumField(listing, const ['engine_size', 'engineSize']),
        minRaw: filters.engineSize,
        maxRaw: filters.engineSize,
      )) {
    return false;
  }
  if (HomeFiltersSnapshot._has(filters.city) &&
      !_ciContains(
        _listingStringField(listing, const ['location', 'city']),
        filters.city!,
      )) {
    return false;
  }
  if (!HomeFiltersSnapshot._isAny(filters.plateType) &&
      !_ciEquals(
        _listingStringField(listing, const ['plate_type', 'plateType']),
        filters.plateType!,
      )) {
    return false;
  }
  if (!HomeFiltersSnapshot._isAny(filters.plateCity) &&
      !_ciContains(
        _listingStringField(listing, const ['plate_city', 'plateCity']),
        filters.plateCity!,
      )) {
    return false;
  }
  if (HomeFiltersSnapshot._has(filters.titleStatus)) {
    if (!_ciEquals(
      _listingStringField(listing, const ['title_status', 'titleStatus']),
      filters.titleStatus!,
    )) {
      return false;
    }
    if (filters.titleStatus == 'damaged' &&
        HomeFiltersSnapshot._has(filters.damagedParts)) {
      final parts = int.tryParse(filters.damagedParts!.trim());
      final listingParts = _listingNumField(
        listing,
        const ['damaged_parts', 'damagedParts'],
      )?.round();
      if (parts == null || listingParts != parts) return false;
    }
  }
  return true;
}

/// Keeps listings that match [filters], preserving input order.
List<Map<String, dynamic>> filterListingsByHomeFilters(
  List<Map<String, dynamic>> source,
  HomeFiltersSnapshot filters,
) {
  if (!filters.hasActiveFilters) return source;
  return source.where((row) => listingMatchesHomeFilters(row, filters)).toList();
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
