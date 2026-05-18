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

  static List<Map<String, dynamic>> _fromServerResponse(Map<String, dynamic> res) {
    final raw = res['saved_searches'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => _serverItemToLocal(Map<String, dynamic>.from(e.cast<String, dynamic>())))
        .toList();
  }

  static Map<String, dynamic> _serverItemToLocal(Map<String, dynamic> row) {
    return {
      'id': (row['id'] ?? '').toString(),
      'name': (row['name'] ?? '').toString(),
      'filters': row['filters'] is Map
          ? Map<String, dynamic>.from((row['filters'] as Map).cast<String, dynamic>())
          : <String, dynamic>{},
      'notify': row['notify'] != false,
      'auto_saved': row['auto_saved'] == true,
      'created_at': row['created_at']?.toString() ?? DateTime.now().toIso8601String(),
    };
  }

  static Future<void> persistLocal(List<Map<String, dynamic>> items) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(localKey, json.encode(items));
  }

  /// Load saved searches: merge local with server when logged in.
  static Future<List<Map<String, dynamic>>> loadMerged() async {
    final sp = await SharedPreferences.getInstance();
    final local = _decodeLocal(sp.getString(localKey));
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
        ? Map<String, dynamic>.from((item['filters'] as Map).cast<String, dynamic>())
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
