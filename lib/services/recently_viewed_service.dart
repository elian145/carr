import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import '../shared/auth/token_store.dart';
import '../shared/listings/listing_identity.dart';

/// Local cache + server sync for recently viewed listings.
class RecentlyViewedService {
  static const String localKey = 'recently_viewed_local_v1';
  static const int maxItems = 40;

  static Future<void> _ensureAuth() async {
    await TokenStore.load();
    if (ApiService.accessToken == null || ApiService.accessToken!.isEmpty) {
      final t = TokenStore.token;
      if (t != null && t.isNotEmpty) {
        await ApiService.setAccessToken(t);
      }
    }
  }

  static List<Map<String, dynamic>> _decode(String? raw) {
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

  /// Record a view locally and on the server (best-effort).
  static Future<void> recordView(
    String listingId, {
    Map<String, dynamic>? snapshot,
  }) async {
    final id = listingId.trim();
    if (id.isEmpty) return;

    await _recordLocal(id, snapshot: snapshot);

    try {
      await _ensureAuth();
      final token = ApiService.accessToken ?? TokenStore.token;
      if (token == null || token.isEmpty) return;
      await ApiService.recordListingView(id);
    } catch (_) {}
  }

  static Future<void> _recordLocal(
    String listingId, {
    Map<String, dynamic>? snapshot,
  }) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final items = _decode(sp.getString(localKey));
      final now = DateTime.now().toIso8601String();

      final without = items
          .where((e) => listingMatchesId(e, listingId) == false)
          .toList();

      final entry = <String, dynamic>{
        'id': listingId,
        'public_id': snapshot != null ? listingPrimaryId(snapshot) : listingId,
        'viewed_at': now,
      };
      if (snapshot != null && snapshot.isNotEmpty) {
        entry['snapshot'] = snapshot;
      }

      without.insert(0, entry);
      if (without.length > maxItems) {
        without.removeRange(maxItems, without.length);
      }
      await sp.setString(localKey, json.encode(without));
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> _loadLocal() async {
    final sp = await SharedPreferences.getInstance();
    final items = _decode(sp.getString(localKey));
    final out = <Map<String, dynamic>>[];
    for (final item in items) {
      final snap = item['snapshot'];
      if (snap is Map) {
        out.add(Map<String, dynamic>.from(snap.cast<String, dynamic>()));
        continue;
      }
      final id = (item['public_id'] ?? item['id'] ?? '').toString();
      if (id.isNotEmpty) {
        out.add({'id': id, 'public_id': id, 'viewed_at': item['viewed_at']});
      }
    }
    return out;
  }

  static Future<List<Map<String, dynamic>>> _hydrateIds(
    List<Map<String, dynamic>> stubs,
  ) async {
    final out = <Map<String, dynamic>>[];
    for (final stub in stubs) {
      final id = listingPrimaryId(stub);
      if (id.isEmpty) continue;
      if ((stub['brand'] ?? '').toString().isNotEmpty ||
          (stub['title'] ?? '').toString().isNotEmpty) {
        out.add(stub);
        continue;
      }
      try {
        final data = await ApiService.getCar(id);
        final inner = data['car'];
        if (inner is Map) {
          out.add(Map<String, dynamic>.from(inner.cast<String, dynamic>()));
        }
      } catch (_) {}
    }
    return out;
  }

  /// Server list merged with local cache (newest first).
  static Future<List<Map<String, dynamic>>> loadMerged() async {
    await _ensureAuth();
    final token = ApiService.accessToken ?? TokenStore.token;

    List<Map<String, dynamic>> serverCars = [];
    if (token != null && token.isNotEmpty) {
      try {
        final data = await ApiService.getRecentlyViewed(page: 1, perPage: maxItems);
        final raw = data['cars'];
        if (raw is List) {
          serverCars = raw
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
              .toList();
        }
      } catch (_) {}
    }

    if (serverCars.isNotEmpty) {
      return serverCars;
    }

    final local = await _loadLocal();
    if (local.isEmpty) return [];

    final hydrated = await _hydrateIds(local);
    return hydrated.isNotEmpty ? hydrated : local;
  }
}
