import '../../shared/i18n/region_spec_labels.dart';
import 'home_filters_query.dart';

/// Trims and drops empty filter strings from persisted / API maps.
String? homeFilterNormalizeStr(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}

/// Normalizes region spec codes for home filter state.
String? homeFilterNormalizeRegionSpecs(String? raw) {
  final rs = homeFilterNormalizeStr(raw)?.toLowerCase();
  if (rs == null || rs.isEmpty || !isValidCarRegionSpecCode(rs)) return null;
  return rs;
}

/// Parsed home filter fields from saved-search or persist maps.
class HomeFilterParsedFields {
  const HomeFilterParsedFields({
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
    this.sortBy,
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
  final String? sortBy;

  factory HomeFilterParsedFields.fromSavedSearchMap(Map<String, dynamic> map) {
    return HomeFilterParsedFields(
      brand: homeFilterNormalizeStr(map['brand']),
      model: homeFilterNormalizeStr(map['model']),
      trim: homeFilterNormalizeStr(map['trim']),
      minPrice: homeFilterNormalizeStr(map['min_price']),
      maxPrice: homeFilterNormalizeStr(map['max_price']),
      minYear: homeFilterNormalizeStr(map['min_year']),
      maxYear: homeFilterNormalizeStr(map['max_year']),
      minMileage: homeFilterNormalizeStr(map['min_mileage']),
      maxMileage: homeFilterNormalizeStr(map['max_mileage']),
      condition: homeFilterNormalizeStr(map['condition']),
      transmission: homeFilterNormalizeStr(map['transmission']),
      fuelType: homeFilterNormalizeStr(map['fuel_type']),
      bodyType: homeFilterNormalizeStr(map['body_type']),
      color: homeFilterNormalizeStr(map['color']),
      driveType: homeFilterNormalizeStr(map['drive_type']),
      regionSpecs: homeFilterNormalizeRegionSpecs(
        homeFilterNormalizeStr(map['region_specs']),
      ),
      cylinderCount: homeFilterNormalizeStr(map['cylinder_count']),
      seating: homeFilterNormalizeStr(map['seating']),
      engineSize: homeFilterNormalizeStr(map['engine_size']),
      city: homeFilterNormalizeStr(map['city']),
      plateType: homeFilterNormalizeStr(map['plate_type']),
      plateCity: homeFilterNormalizeStr(map['plate_city']),
      titleStatus: homeFilterNormalizeStr(map['title_status']),
      damagedParts: homeFilterNormalizeStr(map['damaged_parts']),
      sortBy: homeFilterNormalizeStr(map['sort_by']),
    );
  }

  factory HomeFilterParsedFields.fromHomePersistMap(Map<String, dynamic> map) {
    return HomeFilterParsedFields.fromSavedSearchMap(
      homePersistMapToSavedSearchKeys(map),
    );
  }
}

/// Maps `home_filters_v1` SharedPreferences keys to saved-search keys.
Map<String, dynamic> homePersistMapToSavedSearchKeys(
  Map<String, dynamic> map,
) {
  return <String, dynamic>{
    'brand': map['brand'],
    'model': map['model'],
    'trim': map['trim'],
    'min_price': map['price_min'],
    'max_price': map['price_max'],
    'min_year': map['year_min'],
    'max_year': map['year_max'],
    'min_mileage': map['min_mileage'],
    'max_mileage': map['max_mileage'],
    'condition': map['condition'],
    'transmission': map['transmission'],
    'fuel_type': map['fuel_type'],
    'body_type': map['body_type'],
    'color': map['color'],
    'drive_type': map['drive_type'],
    'region_specs': map['region_specs'],
    'cylinder_count': map['cylinders'],
    'seating': map['seating'],
    'engine_size': map['engine_size'],
    'city': map['city'],
    'plate_type': map['plate_type'],
    'plate_city': map['plate_city'],
    'title_status': map['title_status'],
    'damaged_parts': map['damaged_parts'],
    'sort_by': map['sort_by'],
  };
}

/// Encodes [filters] for `home_filters_v1` SharedPreferences storage.
Map<String, dynamic> homeFilterHomePersistMap(HomeFiltersSnapshot filters) {
  return <String, dynamic>{
    'brand': filters.brand,
    'model': filters.model,
    'trim': filters.trim,
    'price_min': filters.minPrice,
    'price_max': filters.maxPrice,
    'year_min': filters.minYear,
    'year_max': filters.maxYear,
    'min_mileage': filters.minMileage,
    'max_mileage': filters.maxMileage,
    'condition': filters.condition,
    'transmission': filters.transmission,
    'fuel_type': filters.fuelType,
    'body_type': filters.bodyType,
    'color': filters.color,
    'drive_type': filters.driveType,
    'region_specs': filters.regionSpecs,
    'cylinders': filters.cylinderCount,
    'seating': filters.seating,
    'engine_size': filters.engineSize,
    'city': filters.city,
    'plate_type': filters.plateType,
    'plate_city': filters.plateCity,
    'title_status': filters.titleStatus,
    'damaged_parts': filters.damagedParts,
    'sort_by': filters.sortByUi,
  };
}

/// Dropdown value for lists that use `''` for Any.
String homeValidDropdownSelection({
  required String? selected,
  required List<String> available,
}) {
  if (selected == null || selected == 'Any' || selected.isEmpty) {
    return '';
  }
  if (available.contains(selected) && selected != 'Any') {
    return selected;
  }
  final lowerSelected = selected.toLowerCase();
  for (final option in available) {
    if (option != 'Any' && option.toLowerCase() == lowerSelected) {
      return option;
    }
  }
  return '';
}
