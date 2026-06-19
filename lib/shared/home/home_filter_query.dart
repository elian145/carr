import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../car/region_specs.dart';
import 'home_sort_api.dart';

/// Builds `/api/cars` query parameters from persisted home filters (`home_filters_v1`).
class HomeFilterQuery {
  HomeFilterQuery._();

  static const String prefsKey = 'home_filters_v1';

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static Map<String, String> fromPersistMap(
    Map<String, dynamic> map, {
    BuildContext? context,
    bool includeSort = true,
  }) {
    final filters = <String, String>{};

    void put(String key, dynamic value) {
      final s = _str(value);
      if (s != null) filters[key] = s;
    }

    put('brand', map['brand']);
    put('model', map['model']);
    put('trim', map['trim']);
    put('min_price', map['price_min']);
    put('max_price', map['price_max']);
    put('min_year', map['year_min']);
    put('max_year', map['year_max']);
    put('min_mileage', map['min_mileage']);
    put('max_mileage', map['max_mileage']);

    void putLowerIfNotAny(String key, dynamic value) {
      final s = _str(value);
      if (s == null || s.toLowerCase() == 'any') return;
      filters[key] = s.toLowerCase();
    }

    putLowerIfNotAny('condition', map['condition']);
    putLowerIfNotAny('transmission', map['transmission']);
    putLowerIfNotAny('fuel_type', map['fuel_type']);
    putLowerIfNotAny('body_type', map['body_type']);
    putLowerIfNotAny('color', map['color']);
    putLowerIfNotAny('drive_type', map['drive_type']);

    final rs = _str(map['region_specs'])?.toLowerCase();
    if (rs != null && isValidCarRegionSpecCode(rs)) {
      filters['region_specs'] = rs;
    }

    putLowerIfNotAny('cylinder_count', map['cylinders']);
    putLowerIfNotAny('seating', map['seating']);
    putLowerIfNotAny('engine_size', map['engine_size']);
    put('city', map['city']);
    putLowerIfNotAny('plate_type', map['plate_type']);
    putLowerIfNotAny('plate_city', map['plate_city']);

    final titleStatus = _str(map['title_status']);
    if (titleStatus != null) {
      filters['title_status'] = titleStatus;
      if (titleStatus == 'damaged') {
        put('damaged_parts', map['damaged_parts']);
      }
    }

    if (includeSort && context != null) {
      final sortApi = homeSortToApiValue(context, _str(map['sort_by']));
      if (sortApi != null && sortApi.isNotEmpty) {
        filters['sort_by'] = sortApi;
      }
    }

    return filters;
  }

  static Future<Map<String, String>> fromSharedPreferences({
    BuildContext? context,
    bool includeSort = true,
  }) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(prefsKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = json.decode(raw);
      if (decoded is! Map) return {};
      return fromPersistMap(
        Map<String, dynamic>.from(decoded.cast<String, dynamic>()),
        context: context,
        includeSort: includeSort,
      );
    } catch (_) {
      return {};
    }
  }

  /// Number of active home filters (for badge / summary on modern home).
  static Future<int> activeFilterCount({BuildContext? context}) async {
    final q = await fromSharedPreferences(context: context, includeSort: true);
    return q.length;
  }

  /// Client-side filter for exact damaged-parts count (legacy home behavior).
  static List<Map<String, dynamic>> applyDamagedPartsExactFilter(
    List<Map<String, dynamic>> input,
    Map<String, String> query,
  ) {
    final titleStatus = query['title_status']?.trim().toLowerCase();
    if (titleStatus != 'damaged') return input;
    final targetParts = int.tryParse(query['damaged_parts'] ?? '');
    if (targetParts == null) return input;

    return input.where((car) {
      final ts = (car['title_status']?.toString() ?? '').trim().toLowerCase();
      if (ts != 'damaged') return false;
      final parts = int.tryParse(car['damaged_parts']?.toString() ?? '');
      return parts == targetParts;
    }).toList();
  }
}
