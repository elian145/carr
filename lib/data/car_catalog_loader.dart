import 'dart:convert';

import 'package:flutter/services.dart';

import '../shared/debug/app_log.dart';

/// Loads [assets/car_catalog.json] when present (run `python tools/export_car_catalog_json.py`).
/// Embedded [CarCatalog] in `car_catalog.dart` remains the default until the asset is generated.
class CarCatalogLoader {
  CarCatalogLoader._();

  static bool _attempted = false;
  static bool assetAvailable = false;

  static Future<void> ensureLoaded() async {
    if (_attempted) return;
    _attempted = true;
    try {
      final raw = await rootBundle.loadString('assets/car_catalog.json');
      final data = json.decode(raw) as Map<String, dynamic>;
      final brands = data['brands'];
      if (brands is List && brands.isNotEmpty) {
        assetAvailable = true;
        appLog('CarCatalogLoader: assets/car_catalog.json available (${brands.length} brands)');
      }
    } catch (_) {
      appLog('CarCatalogLoader: using embedded CarCatalog (no assets/car_catalog.json)');
    }
  }
}
