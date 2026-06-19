import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'home_filter_query.dart';

/// Read/write `home_filters_v1` prefs.
class HomeFilterPersistence {
  HomeFilterPersistence._();

  static Future<Map<String, dynamic>> loadMap() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(HomeFilterQuery.prefsKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = json.decode(raw);
      if (decoded is! Map) return {};
      return Map<String, dynamic>.from(decoded.cast<String, dynamic>());
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveMap(Map<String, dynamic> map) async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (!hasAnyActive(map)) {
        await sp.remove(HomeFilterQuery.prefsKey);
        return;
      }
      await sp.setString(HomeFilterQuery.prefsKey, json.encode(map));
    } catch (_) {}
  }

  static Future<void> clearAll() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(HomeFilterQuery.prefsKey);
    } catch (_) {}
  }

  static bool hasAnyActive(Map<String, dynamic> map) {
    bool active(String? s) {
      if (s == null) return false;
      final t = s.trim();
      if (t.isEmpty) return false;
      return t.toLowerCase() != 'any';
    }

    for (final entry in map.entries) {
      if (entry.value == null) continue;
      if (active(entry.value.toString())) return true;
    }
    return false;
  }

  /// Returns a copy of [map] with one filter group removed.
  static Map<String, dynamic> clearFilterInMap(
    Map<String, dynamic> map,
    String filterType,
  ) {
    final m = Map<String, dynamic>.from(map);
    switch (filterType) {
      case 'brand':
        m.remove('brand');
        m.remove('model');
        m.remove('trim');
        break;
      case 'model':
        m.remove('model');
        m.remove('trim');
        break;
      case 'trim':
        m.remove('trim');
        break;
      case 'price':
        m.remove('price_min');
        m.remove('price_max');
        break;
      case 'year':
        m.remove('year_min');
        m.remove('year_max');
        break;
      case 'mileage':
        m.remove('min_mileage');
        m.remove('max_mileage');
        break;
      case 'condition':
        m.remove('condition');
        break;
      case 'transmission':
        m.remove('transmission');
        break;
      case 'fuelType':
        m.remove('fuel_type');
        break;
      case 'titleStatus':
        m.remove('title_status');
        m.remove('damaged_parts');
        break;
      case 'damagedParts':
        m.remove('damaged_parts');
        break;
      case 'bodyType':
        m.remove('body_type');
        break;
      case 'color':
        m.remove('color');
        break;
      case 'driveType':
        m.remove('drive_type');
        break;
      case 'regionSpecs':
        m.remove('region_specs');
        break;
      case 'cylinderCount':
        m.remove('cylinders');
        break;
      case 'seating':
        m.remove('seating');
        break;
      case 'engineSize':
        m.remove('engine_size');
        break;
      case 'city':
        m.remove('city');
        break;
      case 'plateType':
        m.remove('plate_type');
        break;
      case 'plateCity':
        m.remove('plate_city');
        break;
      case 'sortBy':
        m.remove('sort_by');
        break;
    }
    return m;
  }

  static Future<Map<String, dynamic>> clearFilter(String filterType) async {
    final current = await loadMap();
    final updated = clearFilterInMap(current, filterType);
    await saveMap(updated);
    return updated;
  }

  static Future<void> updateSort(String? localizedSortLabel) async {
    final map = await loadMap();
    if (localizedSortLabel == null || localizedSortLabel.trim().isEmpty) {
      map.remove('sort_by');
    } else {
      map['sort_by'] = localizedSortLabel.trim();
    }
    await saveMap(map);
  }

  static Future<String?> loadSortLabel() async {
    final map = await loadMap();
    final sort = map['sort_by'];
    if (sort == null) return null;
    final s = sort.toString().trim();
    return s.isEmpty ? null : s;
  }
}
