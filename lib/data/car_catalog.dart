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
    'Alfa Romeo',
    'Aston Martin',
    'Audi',
    'Austin',
    'Avatr',
    'BAIC',
    'BAW',
    'Bentley',
    'Bestune',
    'BMW',
    'Borgward',
    'Brilliance',
    'Bugatti',
    'Buick',
    'BYD',
    'Cadillac',
    'CEVO Mobility',
    'Changan',
    'Chery',
    'Chevrolet',
    'Chrysler',
    'Citroen',
    'CMC',
    'Dadi Auto',
    'Daewoo',
    'Daihatsu',
    'Deepal',
    'DENZA',
    'DFSK',
    'Dodge',
    'Dongfeng',
    'EXEED',
    'FAW',
    'Ferrari',
    'Fiat',
    'Ford',
    'Forthing',
    'Foton',
    'GAC',
    'GAZ',
    'Geely',
    'Genesis',
    'GMC',
    'GWM',
    'Hafei',
    'Haima',
    'HAVAL',
    'Hawtai',
    'Higer',
    'Hino',
    'Honda',
    'Hongqi',
    'Huanghai',
    'Hummer',
    'Hyptec',
    'Hyundai',
    'Ineos',
    'Infiniti',
    'Iran Khodro',
    'Isuzu',
    'IVECO',
    'JAC',
    'JAECOO',
    'Jaguar',
    'Jeep',
    'Jetour',
    'Jinbei',
    'JMC',
    'Jonway',
    'KAIYI',
    'Karry',
    'Kawasaki',
    'KAWEI',
    'Kia',
    'King Long',
    'Lada',
    'Lamborghini',
    'Land Rover',
    'Lexus',
    'Lifan',
    'Lincoln',
    'LYNK & CO',
    'Maserati',
    'Maxus',
    'Maybach',
    'Mazda',
    'McLaren',
    'Mercedes-Benz',
    'Mercury',
    'MG',
    'MHERO',
    'MINI',
    'Mitsubishi',
    'Mitsuoka',
    'Morris',
    'Neta',
    'Nissan',
    'Oldsmobile',
    'OMODA',
    'Opel',
    'ORA',
    'Peugeot',
    'POER',
    'Polaris',
    'Polarsun',
    'Polestar',
    'Pontiac',
    'Porsche',
    'Proton',
    'Ram',
    'Renault',
    'Renault Samsung Motors',
    'Roewe',
    'Rolls Royce',
    'Rox',
    'Saab',
    'Saipa',
    'Saturn',
    'Scion',
    'Seat',
    'Skoda',
    'Smart',
    'Soueast',
    'Ssangyong',
    'Subaru',
    'Suzuki',
    'SWM Motors',
    'TANK',
    'Tata',
    'Tesla',
    'Toyota',
    'UAZ',
    'Vanderhall',
    'Volkswagen',
    'Volvo',
    'Voyah',
    'Wuling',
    'XEV',
    'Xiaomi',
    'XPeng',
    'YANGWANG',
    'Zimmer',
    'Zotye',
    'ZX AUTO',
    'Zyle Daewoo Commercial Vehicle',
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