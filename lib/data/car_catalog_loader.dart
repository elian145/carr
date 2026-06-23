import 'dart:convert';

import 'package:flutter/services.dart';

import 'car_catalog.dart';
import '../shared/debug/app_log.dart';

/// Loads [assets/car_catalog.json] when present.
///
/// Regenerate with: `dart run bin/export_car_catalog.dart`
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
      final models = data['models'];
      final hasModels = models is Map && models.isNotEmpty;
      if (!hasModels) {
        appLog(
          'CarCatalogLoader: assets/car_catalog.json missing models — using embedded catalog',
        );
        return;
      }
      CarCatalog.applyCatalogFromAsset(data);
      assetAvailable = true;
      final brandCount = CarCatalog.brands.length;
      final modelGroupCount = CarCatalog.models.length;
      appLog(
        'CarCatalogLoader: applied asset catalog ($brandCount brands, $modelGroupCount model groups)',
      );
    } catch (e, st) {
      logNonFatal(e, st, 'CarCatalogLoader');
      appLog('CarCatalogLoader: using embedded CarCatalog');
    }
  }
}
