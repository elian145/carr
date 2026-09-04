import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'car_catalog.dart';
import '../services/api_service.dart';
import '../services/config.dart';
import '../shared/debug/app_log.dart';

/// Parses [assets/car_catalog.json] text. Top-level for [compute].
Map<String, dynamic> parseCarCatalogJsonString(String raw) {
  final decoded = json.decode(raw);
  if (decoded is! Map) {
    throw const FormatException('car_catalog.json root must be a JSON object');
  }
  return Map<String, dynamic>.from(decoded);
}

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
      // Large catalog JSON: decode off the UI isolate (same pattern as CarSpecIndex).
      final data = await compute(parseCarCatalogJsonString, raw);
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
    if (const bool.fromEnvironment('FLUTTER_TEST')) return;

    String base;
    try {
      base = apiBase().trim();
    } catch (_) {
      return;
    }
    if (base.isEmpty) return;

    try {
      final brandsUri = Uri.parse('$base/api/catalog/brands');
      final brandsRes = await ApiService.getHttp(brandsUri);
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
      final brandByLower = <String, String>{};
      for (final row in brandRows) {
        if (row is! Map) continue;
        final name = '${row['name'] ?? ''}'.trim();
        if (name.isEmpty) continue;
        brandNames.add(name);
        brandByLower[name.toLowerCase()] = name;
      }

      // Fetch ALL models in a single request instead of one call per brand
      // (previously an N+1 that was slow on first home/sell open).
      final modelsByBrand = <String, List<String>>{};
      try {
        final allModelsUri = Uri.parse('$base/api/catalog/models');
        final allModelsRes = await ApiService.getHttp(allModelsUri);
        if (allModelsRes.statusCode == 200) {
          final body = json.decode(allModelsRes.body);
          final rows = body is Map ? body['models'] : null;
          if (rows is List) {
            for (final m in rows) {
              if (m is! Map) continue;
              final mn = '${m['name'] ?? ''}'.trim();
              final bn = '${m['brand_name'] ?? ''}'.trim();
              if (mn.isEmpty || bn.isEmpty) continue;
              final brandKey = brandByLower[bn.toLowerCase()] ?? bn;
              (modelsByBrand[brandKey] ??= <String>[]).add(mn);
            }
          }
        }
      } on TimeoutException catch (e) {
        appLog('CarCatalogLoader: remote models timed out ($e)');
      } catch (e, st) {
        logNonFatal(e, st, 'CarCatalogLoader.models');
      }

      // Fall back to the bundled asset catalog for any brand the API returned
      // no models for, so the picker is never emptier than before.
      final modelsMap = <String, List<String>>{};
      for (final name in brandNames) {
        final remote = modelsByBrand[name];
        modelsMap[name] = (remote != null && remote.isNotEmpty)
            ? remote
            : (CarCatalog.models[name] ?? const <String>[]);
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
    } on TimeoutException catch (e) {
      appLog('CarCatalogLoader: remote overlay timed out ($e)');
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
