import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

/// Local cache + server sync for saved searches.
class SavedSearchService {
  static const String localKey = 'saved_searches_v1';

  static List<Map<String, dynamic>> _decodeLocal(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = json.decode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Map<String, dynamic> normalizeFilters(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return {};
    final out = <String, dynamic>{};
    raw.forEach((key, value) {
      if (value == null) return;
      final s = value.toString().trim();
      if (s.isEmpty || s.toLowerCase() == 'any') return;
      out[key] = value;
    });
    return Map.fromEntries(
      out.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  static bool filtersEqual(
    Map<String, dynamic>? a,
    Map<String, dynamic>? b,
  ) {
    return json.encode(normalizeFilters(a)) == json.encode(normalizeFilters(b));
  }

  /// One entry per unique filter set (prefers server UUID ids).
  static List<Map<String, dynamic>> dedupeByFilters(
    List<Map<String, dynamic>> items,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final item in items) {
      final filters = item['filters'] is Map
          ? Map<String, dynamic>.from(
              (item['filters'] as Map).cast<String, dynamic>(),
            )
          : <String, dynamic>{};
      final idx = out.indexWhere(
        (e) => filtersEqual(
          e['filters'] is Map
              ? Map<String, dynamic>.from(
                  (e['filters'] as Map).cast<String, dynamic>(),
                )
              : null,
          filters,
        ),
      );
      if (idx >= 0) {
        final existingId = (out[idx]['id'] ?? '').toString();
        final newId = (item['id'] ?? '').toString();
        if (!_isServerId(existingId) && _isServerId(newId)) {
          out[idx]['id'] = newId;
        }
        continue;
      }
      out.add(Map<String, dynamic>.from(item));
    }
    return out;
  }

  static List<Map<String, dynamic>> _fromServerResponse(Map<String, dynamic> res) {
    final raw = res['saved_searches'];
    if (raw is! List) return [];
    return dedupeByFilters(
      raw
          .whereType<Map>()
          .map((e) => _serverItemToLocal(Map<String, dynamic>.from(e.cast<String, dynamic>())))
          .toList(),
    );
  }

  static Map<String, dynamic> _serverItemToLocal(Map<String, dynamic> row) {
    return {
      'id': (row['id'] ?? '').toString(),
      'name': (row['name'] ?? '').toString(),
      'filters': row['filters'] is Map
          ? normalizeFilters(
              Map<String, dynamic>.from((row['filters'] as Map).cast<String, dynamic>()),
            )
          : <String, dynamic>{},
      'notify': row['notify'] != false,
      'auto_saved': row['auto_saved'] == true,
      'created_at': row['created_at']?.toString() ?? DateTime.now().toIso8601String(),
    };
  }

  static Future<void> persistLocal(List<Map<String, dynamic>> items) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(localKey, json.encode(dedupeByFilters(items)));
  }

  /// Load saved searches: merge local with server when logged in.
  static Future<List<Map<String, dynamic>>> loadMerged() async {
    final sp = await SharedPreferences.getInstance();
    final local = dedupeByFilters(_decodeLocal(sp.getString(localKey)));
    final token = ApiService.accessToken;
    if (token == null || token.isEmpty) {
      return local;
    }

    try {
      if (local.isNotEmpty) {
        final synced = await ApiService.syncSavedSearches(local);
        final merged = _fromServerResponse(synced);
        await persistLocal(merged);
        return merged;
      }
      final res = await ApiService.getSavedSearches();
      final server = _fromServerResponse(res);
      await persistLocal(server);
      return server;
    } catch (_) {
      return local;
    }
  }

  static bool _isServerId(String id) {
    final s = id.trim();
    return s.contains('-') && s.length >= 32;
  }

  static Future<void> pushItemToServer(Map<String, dynamic> item) async {
    final token = ApiService.accessToken;
    if (token == null || token.isEmpty) return;

    final id = (item['id'] ?? '').toString();
    final name = (item['name'] ?? '').toString();
    final filters = item['filters'] is Map
        ? normalizeFilters(
            Map<String, dynamic>.from((item['filters'] as Map).cast<String, dynamic>()),
          )
        : <String, dynamic>{};
    final notify = item['notify'] != false;
    final autoSaved = item['auto_saved'] == true;

    try {
      if (_isServerId(id)) {
        await ApiService.updateSavedSearch(
          id,
          name: name,
          filters: filters,
          notify: notify,
          autoSaved: autoSaved,
        );
      } else {
        final res = await ApiService.createSavedSearch(
          name: name,
          filters: filters,
          notify: notify,
          autoSaved: autoSaved,
        );
        final created = res['saved_search'];
        if (created is Map) {
          item['id'] = (created['id'] ?? id).toString();
        }
      }
    } catch (_) {}
  }

  static Future<void> deleteOnServer(String id) async {
    if (!_isServerId(id)) return;
    final token = ApiService.accessToken;
    if (token == null || token.isEmpty) return;
    try {
      await ApiService.deleteSavedSearch(id);
    } catch (_) {}
  }
}
