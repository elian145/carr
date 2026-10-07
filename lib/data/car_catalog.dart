import '../services/iqcars_overlay.dart';

/// Car brands, models, and trims loaded from [assets/car_catalog.json].
/// Regenerate asset: `flutter pub run bin/export_car_catalog.dart`
/// Legacy Dart regeneration: `python tools/extract_car_catalog.py` (then export).
class CarCatalog {
  CarCatalog._();

  static List<String>? _runtimeBrands;
  static Map<String, List<String>>? _runtimeModels;
  static Map<String, Map<String, List<String>>>? _runtimeTrims;

  /// Approved IQ Cars additions (additive; [IqCarsOverlay.empty] until applied).
  static IqCarsOverlay _iqOverlay = IqCarsOverlay.empty;

  /// Baseline + overlay trims, built once per (baseline, overlay) pair.
  static Map<String, Map<String, List<String>>>? _mergedTrims;

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
    _iqOverlay = IqCarsOverlay.empty;
    _mergedTrims = null;
  }

  static void resetBrandsOverrideForTest() => resetCatalogOverrideForTest();

  static Map<String, List<String>> get models =>
      _runtimeModels ?? _embeddedModels;

  /// The catalog's own trims, exactly as loaded (no IQ Cars additions).
  static Map<String, Map<String, List<String>>> get baselineTrimsByBrandModel =>
      _runtimeTrims ?? _embeddedTrimsByBrandModel;

  /// Catalog trims **plus** the approved IQ Cars additions (additive only).
  ///
  /// Built once per (catalog, overlay) pair and then returned as-is, so Search /
  /// Sell rebuilds stay O(1). Models that have no catalog trims get just the
  /// additions here (Sell's [trimsFor] additionally keeps its `Base` entry).
  static Map<String, Map<String, List<String>>> get trimsByBrandModel {
    final base = baselineTrimsByBrandModel;
    if (_iqOverlay.isEmpty) return base;
    return _mergedTrims ??= _mergeTrimsWithOverlay(base, _iqOverlay);
  }

  static Map<String, Map<String, List<String>>> _mergeTrimsWithOverlay(
    Map<String, Map<String, List<String>>> base,
    IqCarsOverlay overlay,
  ) {
    final merged = <String, Map<String, List<String>>>{
      for (final e in base.entries)
        e.key: Map<String, List<String>>.of(e.value),
    };
    for (final brandEntry in overlay.entries) {
      for (final modelEntry in brandEntry.value.entries) {
        final brand = brandEntry.key;
        final model = modelEntry.key;
        if (modelEntry.value.trims.isEmpty) continue;
        final existing = base[brand]?[model] ?? const <String>[];
        final next = overlay.mergeTrims(existing, brand, model);
        if (identical(next, existing)) continue;
        (merged[brand] ??= <String, List<String>>{})[model] = next;
      }
    }
    return merged;
  }

  /// Applies the approved IQ Cars additions (idempotent; pass
  /// [IqCarsOverlay.empty] to go back to the plain catalog).
  static void applyIqCarsOverlay(IqCarsOverlay overlay) {
    if (identical(overlay, _iqOverlay)) return;
    _iqOverlay = overlay;
    _mergedTrims = null;
  }

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
        _mergedTrims = null;
      }
    }
  }

  /// The catalog's own trims for a model (no IQ Cars additions); returns
  /// ['Base'] only when no trim data exists.
  static List<String> baselineTrimsFor(String? brand, String? model) {
    if (brand == null || model == null) return ['Base'];
    return baselineTrimsByBrandModel[brand]?[model] ?? ['Base'];
  }

  /// Trims for a given brand and model; returns ['Base'] only when no trim data
  /// exists. Approved IQ Cars trims are appended (catalog order is preserved and
  /// nothing is removed); a model without catalog trims keeps its `Base` entry.
  static List<String> trimsFor(String? brand, String? model) {
    if (brand == null || model == null) return ['Base'];
    final base = baselineTrimsByBrandModel[brand]?[model];
    final merged = trimsByBrandModel[brand]?[model];
    if (merged == null) return base ?? ['Base'];
    if (base == null) return <String>['Base', ...merged];
    return merged;
  }
}