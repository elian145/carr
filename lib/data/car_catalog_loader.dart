import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'car_catalog.dart';
import '../services/config.dart';
import '../shared/debug/app_log.dart';

/// Loads [assets/car_catalog.json] when present, then optionally overlays
/// active brands/models from `GET /api/catalog/*` when [apiBase] is set.
///
/// Regenerate asset with: `dart run bin/export_car_catalog.dart`
///
/// Call [ensureLoaded] from home/sell flows (not app bootstrap) so cold start
/// is not blocked by asset decode or remote catalog fetches.
class CarCatalogLoader {
  CarCatalogLoader._();

  static Future<void>? _loading;
  static bool assetAvailable = false;
  static bool remoteApplied = false;
  static bool remoteOverlayStarted = false;

  /// Loads the local asset catalog (idempotent). Remote API overlay runs in
  /// the background and does not delay this future.
  static Future<void> ensureLoaded() {
    return _loading ??= _loadAssetCatalog();
  }

  static Future<void> _loadAssetCatalog() async {
    try {
      final raw = await rootBundle.loadString('assets/car_catalog.json');
      final data = json.decode(raw) as Map<String, dynamic>;
      final models = data['models'];
      final hasModels = models is Map && models.isNotEmpty;
      if (!hasModels) {
        appLog(
          'CarCatalogLoader: assets/car_catalog.json missing models — using embedded catalog',
        );
      } else {
        CarCatalog.applyCatalogFromAsset(data);
        assetAvailable = true;
        final brandCount = CarCatalog.brands.length;
        final modelGroupCount = CarCatalog.models.length;
        appLog(
          'CarCatalogLoader: applied asset catalog ($brandCount brands, $modelGroupCount model groups)',
        );
      }
    } catch (e, st) {
      logNonFatal(e, st, 'CarCatalogLoader');
      appLog('CarCatalogLoader: using embedded CarCatalog');
    }

    // Never await remote overlay on the critical path (cold Render / N+1 models).
    if (!remoteOverlayStarted) {
      remoteOverlayStarted = true;
      unawaited(_overlayFromApi());
    }
  }

  static Future<void> _overlayFromApi() async {
    String base;
    try {
      base = apiBase().trim();
    } catch (_) {
      return;
    }
    if (base.isEmpty) return;

    try {
      final brandsUri = Uri.parse('$base/api/catalog/brands');
      final brandsRes = await http.get(brandsUri).timeout(const Duration(seconds: 8));
      if (brandsRes.statusCode != 200) {
        appLog(
          'CarCatalogLoader: remote brands HTTP ${brandsRes.statusCode} — keeping asset catalog',
        );
        return;
      }
      final brandsBody = json.decode(brandsRes.body);
      if (brandsBody is! Map) return;
      final brandRows = brandsBody['brands'];
      if (brandRows is! List || brandRows.isEmpty) return;

      final brandNames = <String>[];
      final modelsMap = <String, List<String>>{};
      for (final row in brandRows) {
        if (row is! Map) continue;
        final name = '${row['name'] ?? ''}'.trim();
        if (name.isEmpty) continue;
        brandNames.add(name);
        final modelsUri = Uri.parse('$base/api/catalog/models').replace(
          queryParameters: {'brand': name},
        );
        final modelsRes =
            await http.get(modelsUri).timeout(const Duration(seconds: 8));
        if (modelsRes.statusCode != 200) {
          modelsMap[name] = CarCatalog.models[name] ?? const <String>[];
          continue;
        }
        final modelsBody = json.decode(modelsRes.body);
        final modelRows =
            modelsBody is Map ? modelsBody['models'] : null;
        final names = <String>[];
        if (modelRows is List) {
          for (final m in modelRows) {
            if (m is Map) {
              final mn = '${m['name'] ?? ''}'.trim();
              if (mn.isNotEmpty) names.add(mn);
            } else {
              final mn = '$m'.trim();
              if (mn.isNotEmpty) names.add(mn);
            }
          }
        }
        modelsMap[name] =
            names.isNotEmpty ? names : (CarCatalog.models[name] ?? const <String>[]);
      }

      if (brandNames.isEmpty) return;

      // Preserve asset/runtime trims; only replace brands + models from API.
      final existingTrims = <String, Map<String, List<String>>>{};
      for (final b in CarCatalog.brands) {
        final byModel = <String, List<String>>{};
        for (final m in (CarCatalog.models[b] ?? const <String>[])) {
          final trims = CarCatalog.trimsFor(b, m);
          if (trims.isNotEmpty && !(trims.length == 1 && trims.first == 'Base')) {
            byModel[m] = List<String>.from(trims);
          } else if (CarCatalog.trimsByBrandModel[b]?[m] != null) {
            byModel[m] = List<String>.from(CarCatalog.trimsByBrandModel[b]![m]!);
          }
        }
        if (byModel.isNotEmpty) existingTrims[b] = byModel;
      }

      CarCatalog.applyCatalogFromAsset({
        'brands': brandNames,
        'models': modelsMap,
        'trimsByBrandModel': existingTrims,
      });
      remoteApplied = true;
      appLog(
        'CarCatalogLoader: overlaid API catalog (${brandNames.length} brands)',
      );
    } catch (e, st) {
      logNonFatal(e, st, 'CarCatalogLoader.remote');
      appLog('CarCatalogLoader: remote overlay skipped');
    }
  }

  @visibleForTesting
  static void debugResetForTest() {
    _loading = null;
    assetAvailable = false;
    remoteApplied = false;
    remoteOverlayStarted = false;
  }
}
