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

  static const Object _unset = Object();

  HomeFilterFields copyWith({
    Object? brand = _unset,
    Object? model = _unset,
    Object? trim = _unset,
    Object? priceMin = _unset,
    Object? priceMax = _unset,
    Object? yearMin = _unset,
    Object? yearMax = _unset,
    Object? minMileage = _unset,
    Object? maxMileage = _unset,
    Object? condition = _unset,
    Object? transmission = _unset,
    Object? fuelType = _unset,
    Object? bodyType = _unset,
    Object? color = _unset,
    Object? driveType = _unset,
    Object? regionSpecs = _unset,
    Object? cylinders = _unset,
    Object? seating = _unset,
    Object? engineSize = _unset,
    Object? city = _unset,
    Object? plateType = _unset,
    Object? plateCity = _unset,
    Object? titleStatus = _unset,
    Object? damagedParts = _unset,
    Object? sortBy = _unset,
  }) {
    String? pick(Object? key, String? current) =>
        identical(key, _unset) ? current : key as String?;
    return HomeFilterFields(
      brand: pick(brand, this.brand),
      model: pick(model, this.model),
      trim: pick(trim, this.trim),
      priceMin: pick(priceMin, this.priceMin),
      priceMax: pick(priceMax, this.priceMax),
      yearMin: pick(yearMin, this.yearMin),
      yearMax: pick(yearMax, this.yearMax),
      minMileage: pick(minMileage, this.minMileage),
      maxMileage: pick(maxMileage, this.maxMileage),
      condition: pick(condition, this.condition),
      transmission: pick(transmission, this.transmission),
      fuelType: pick(fuelType, this.fuelType),
      bodyType: pick(bodyType, this.bodyType),
      color: pick(color, this.color),
      driveType: pick(driveType, this.driveType),
      regionSpecs: pick(regionSpecs, this.regionSpecs),
      cylinders: pick(cylinders, this.cylinders),
      seating: pick(seating, this.seating),
      engineSize: pick(engineSize, this.engineSize),
      city: pick(city, this.city),
      plateType: pick(plateType, this.plateType),
      plateCity: pick(plateCity, this.plateCity),
      titleStatus: pick(titleStatus, this.titleStatus),
      damagedParts: pick(damagedParts, this.damagedParts),
      sortBy: pick(sortBy, this.sortBy),
    );
  }

  HomeFilterFields cleared() => const HomeFilterFields();
}
