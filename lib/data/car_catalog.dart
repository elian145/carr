/// Car brands, models, and trims loaded from [assets/car_catalog.json].
/// Regenerate asset: `flutter pub run bin/export_car_catalog.dart`
/// Legacy Dart regeneration: `python tools/extract_car_catalog.py` (then export).
class CarCatalog {
  CarCatalog._();

  static List<String>? _runtimeBrands;
  static Map<String, List<String>>? _runtimeModels;
  static Map<String, Map<String, List<String>>>? _runtimeTrims;

  static List<String> get brands => _runtimeBrands ?? _embeddedBrands;

  static final List<String> _embeddedBrands = [
    'Acura',
    'Aston Martin',
    'Audi',
    'Baic',
    'Baojun',
    'Bentley',
    'BMW',
    'Buick',
    'BYD',
    'Cadillac',
    'Changan',
    'Chery',
    'Chevrolet',
    'Chrysler',
    'Citroën',
    'Dacia',
    'Daewoo',
    'Dodge',
    'Dongfeng',
    'FAW',
    'Ferrari',
    'Ford',
    'Foton',
    'Gac',
    'Geely',
    'Genesis',
    'GMC',
    'Great Wall',
    'Gwm',
    'Haval',
    'Honda',
    'Hyundai',
    'Infiniti',
    'Isuzu',
    'Jaguar',
    'Jeep',
    'Jetour',
    'Kia',
    'Lada',
    'Lamborghini',
    'Land Rover',
    'Leapmotor',
    'Lexus',
    'Li Auto',
    'Lincoln',
    'Lucid',
    'Mahindra',
    'Maserati',
    'Mazda',
    'Mercedes Maybach',
    'Mercedes-Benz',
    'Mg',
    'Mini',
    'Mitsubishi',
    'Nio',
    'Nissan',
    'Perodua',
    'Peugeot',
    'Polestar',
    'Porsche',
    'Proton',
    'RAM',
    'Renault',
    'Rivian',
    'Roewe',
    'Rolls-Royce',
    'SEAT',
    'Smart',
    'Soueast',
    'SsangYong',
    'Subaru',
    'Suzuki',
    'Tata',
    'Tesla',
    'Toyota',
    'VinFast',
    'Volkswagen',
    'Volvo',
    'Wuling',
    'XPeng',
    'ZAZ',
    'Škoda',
  ];

  static const Map<String, List<String>> _embeddedModels = {};

  static const Map<String, Map<String, List<String>>> _embeddedTrimsByBrandModel = {};

  /// Clears asset overrides (tests only).
  static void resetCatalogOverrideForTest() {
    _runtimeBrands = null;
    _runtimeModels = null;
    _runtimeTrims = null;
  }

  static void resetBrandsOverrideForTest() => resetCatalogOverrideForTest();

  static Map<String, List<String>> get models =>
      _runtimeModels ?? _embeddedModels;

  static Map<String, Map<String, List<String>>> get trimsByBrandModel =>
      _runtimeTrims ?? _embeddedTrimsByBrandModel;

  /// Applies catalog sections from decoded asset JSON.
  static void applyCatalogFromAsset(Map<String, dynamic> data) {
    final brands = data['brands'];
    if (brands is List && brands.isNotEmpty) {
      _runtimeBrands = List.unmodifiable(
        brands.map((e) => e.toString()).toList(growable: false),
      );
    }

    final models = data['models'];
    if (models is Map && models.isNotEmpty) {
      final parsed = <String, List<String>>{};
      for (final entry in models.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is! List) continue;
        parsed[key] = value.map((e) => e.toString()).toList(growable: false);
      }
      if (parsed.isNotEmpty) {
        _runtimeModels = parsed;
      }
    }

    final trims = data['trimsByBrandModel'];
    if (trims is Map && trims.isNotEmpty) {
      final parsed = <String, Map<String, List<String>>>{};
      for (final brandEntry in trims.entries) {
        final brand = brandEntry.key.toString();
        final modelMap = brandEntry.value;
        if (modelMap is! Map) continue;
        final modelsForBrand = <String, List<String>>{};
        for (final modelEntry in modelMap.entries) {
          final model = modelEntry.key.toString();
          final trimList = modelEntry.value;
          if (trimList is! List) continue;
          modelsForBrand[model] =
              trimList.map((e) => e.toString()).toList(growable: false);
        }
        if (modelsForBrand.isNotEmpty) {
          parsed[brand] = modelsForBrand;
        }
      }
      if (parsed.isNotEmpty) {
        _runtimeTrims = parsed;
      }
    }
  }

  /// Trims for a given brand and model; returns ['Base'] only when no trim data exists.
  static List<String> trimsFor(String? brand, String? model) {
    if (brand == null || model == null) return ['Base'];
    return trimsByBrandModel[brand]?[model] ?? ['Base'];
  }
}