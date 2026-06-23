import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/debug/app_log.dart';

/// Persists saved-search filters for the home feed (prefs bridge, not UI state).
abstract final class SavedSearchHomeBridge {
  static const String pendingFetchKey = 'home_pending_saved_search_fetch_v1';
  static const String oneTimeFiltersKey = 'home_apply_filters_once_v1';

  static Future<void> markPendingFetch() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(pendingFetchKey, true);
    } catch (e, st) {
      logNonFatal(e, st);
    }
  }

  static Future<bool> consumePendingFetch() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final pending = sp.getBool(pendingFetchKey) ?? false;
      if (pending) {
        await sp.remove(pendingFetchKey);
      }
      return pending;
    } catch (e, st) {
      logNonFatal(e, st);
      return false;
    }
  }

  static Future<Map<String, dynamic>?> consumeOneTimeFilters() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(oneTimeFiltersKey);
      if (raw == null || raw.isEmpty) return null;
      await sp.remove(oneTimeFiltersKey);
      final decoded = json.decode(raw);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded.cast<String, dynamic>());
    } catch (e, st) {
      logNonFatal(e, st);
      return null;
    }
  }

  /// One-time saved-search apply (not restored on next app launch).
  static Future<void> persistFiltersForHome(Map<String, dynamic> filters) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final map = <String, dynamic>{
        'brand': filters['brand'],
        'model': filters['model'],
        'trim': filters['trim'],
        'price_min': filters['min_price'] ?? filters['price_min'],
        'price_max': filters['max_price'] ?? filters['price_max'],
        'year_min': filters['min_year'] ?? filters['year_min'],
        'year_max': filters['max_year'] ?? filters['year_max'],
        'min_mileage': filters['min_mileage'],
        'max_mileage': filters['max_mileage'],
        'condition': filters['condition'],
        'transmission': filters['transmission'],
        'fuel_type': filters['fuel_type'],
        'body_type': filters['body_type'],
        'color': filters['color'],
        'drive_type': filters['drive_type'],
        'region_specs': filters['region_specs'],
        'cylinders': filters['cylinder_count'] ?? filters['cylinders'],
        'seating': filters['seating'],
        'engine_size': filters['engine_size'],
        'city': filters['city'],
        'plate_type': filters['plate_type'],
        'plate_city': filters['plate_city'],
        'title_status': filters['title_status'],
        'damaged_parts': filters['damaged_parts'],
        'sort_by': filters['sort_by'],
      };
      map.removeWhere((_, v) => v == null || v.toString().trim().isEmpty);
      await sp.remove('home_filters_v1');
      await sp.setString(oneTimeFiltersKey, json.encode(map));
      await markPendingFetch();
    } catch (e, st) {
      logNonFatal(e, st);
    }
  }

  /// Clears orphaned one-time keys when the app starts before Home mounts.
  static Future<void> clearOrphanedStartupKeys() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(oneTimeFiltersKey);
      await sp.remove(pendingFetchKey);
    } catch (e, st) {
      logNonFatal(e, st);
    }
  }
}
