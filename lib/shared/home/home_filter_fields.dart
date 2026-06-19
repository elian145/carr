import 'home_filter_persistence.dart';

/// In-memory home filter values (persisted as `home_filters_v1`).
class HomeFilterFields {
  const HomeFilterFields({
    this.brand,
    this.model,
    this.trim,
    this.priceMin,
    this.priceMax,
    this.yearMin,
    this.yearMax,
    this.minMileage,
    this.maxMileage,
    this.condition,
    this.transmission,
    this.fuelType,
    this.bodyType,
    this.color,
    this.driveType,
    this.regionSpecs,
    this.cylinders,
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
  final String? priceMin;
  final String? priceMax;
  final String? yearMin;
  final String? yearMax;
  final String? minMileage;
  final String? maxMileage;
  final String? condition;
  final String? transmission;
  final String? fuelType;
  final String? bodyType;
  final String? color;
  final String? driveType;
  final String? regionSpecs;
  final String? cylinders;
  final String? seating;
  final String? engineSize;
  final String? city;
  final String? plateType;
  final String? plateCity;
  final String? titleStatus;
  final String? damagedParts;
  final String? sortBy;

  static String? _str(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  factory HomeFilterFields.fromPersistMap(Map<String, dynamic> map) {
    return HomeFilterFields(
      brand: _str(map['brand']),
      model: _str(map['model']),
      trim: _str(map['trim']),
      priceMin: _str(map['price_min']),
      priceMax: _str(map['price_max']),
      yearMin: _str(map['year_min']),
      yearMax: _str(map['year_max']),
      minMileage: _str(map['min_mileage']),
      maxMileage: _str(map['max_mileage']),
      condition: _str(map['condition']),
      transmission: _str(map['transmission']),
      fuelType: _str(map['fuel_type']),
      bodyType: _str(map['body_type']),
      color: _str(map['color']),
      driveType: _str(map['drive_type']),
      regionSpecs: _str(map['region_specs']),
      cylinders: _str(map['cylinders']),
      seating: _str(map['seating']),
      engineSize: _str(map['engine_size']),
      city: _str(map['city']),
      plateType: _str(map['plate_type']),
      plateCity: _str(map['plate_city']),
      titleStatus: _str(map['title_status']),
      damagedParts: _str(map['damaged_parts']),
      sortBy: _str(map['sort_by']),
    );
  }

  /// Saved-search payloads use `min_price`, `cylinder_count`, etc.
  factory HomeFilterFields.fromSavedSearchMap(Map<String, dynamic> map) {
    return HomeFilterFields(
      brand: _str(map['brand']),
      model: _str(map['model']),
      trim: _str(map['trim']),
      priceMin: _str(map['min_price'] ?? map['price_min']),
      priceMax: _str(map['max_price'] ?? map['price_max']),
      yearMin: _str(map['min_year'] ?? map['year_min']),
      yearMax: _str(map['max_year'] ?? map['year_max']),
      minMileage: _str(map['min_mileage']),
      maxMileage: _str(map['max_mileage']),
      condition: _str(map['condition']),
      transmission: _str(map['transmission']),
      fuelType: _str(map['fuel_type']),
      bodyType: _str(map['body_type']),
      color: _str(map['color']),
      driveType: _str(map['drive_type']),
      regionSpecs: _str(map['region_specs']),
      cylinders: _str(map['cylinder_count'] ?? map['cylinders']),
      seating: _str(map['seating']),
      engineSize: _str(map['engine_size']),
      city: _str(map['city']),
      plateType: _str(map['plate_type']),
      plateCity: _str(map['plate_city']),
      titleStatus: _str(map['title_status']),
      damagedParts: _str(map['damaged_parts']),
      sortBy: _str(map['sort_by']),
    );
  }

  Map<String, dynamic> toPersistMap() {
    return {
      'brand': brand,
      'model': model,
      'trim': trim,
      'price_min': priceMin,
      'price_max': priceMax,
      'year_min': yearMin,
      'year_max': yearMax,
      'min_mileage': minMileage,
      'max_mileage': maxMileage,
      'condition': condition,
      'transmission': transmission,
      'fuel_type': fuelType,
      'body_type': bodyType,
      'color': color,
      'drive_type': driveType,
      'region_specs': regionSpecs,
      'cylinders': cylinders,
      'seating': seating,
      'engine_size': engineSize,
      'city': city,
      'plate_type': plateType,
      'plate_city': plateCity,
      'title_status': titleStatus,
      'damaged_parts': damagedParts,
      'sort_by': sortBy,
    };
  }

  static Future<HomeFilterFields> load() async {
    final map = await HomeFilterPersistence.loadMap();
    return HomeFilterFields.fromPersistMap(map);
  }

  Future<void> save() async {
    await HomeFilterPersistence.saveMap(toPersistMap());
  }

  bool get hasAnyActive => HomeFilterPersistence.hasAnyActive(toPersistMap());
}
