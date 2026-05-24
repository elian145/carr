import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import '../shared/auth/token_store.dart';
import '../shared/listings/listing_events.dart';
import '../shared/listings/listing_identity.dart';

/// Local cache + server sync for recently viewed listings.
class RecentlyViewedService {
  static const String localKey = 'recently_viewed_local_v1';
  static const int maxItems = 40;
  static bool _deleteHandlerRegistered = false;

  static void _ensureDeleteHandlerRegistered() {
    if (_deleteHandlerRegistered) return;
    _deleteHandlerRegistered = true;
    ListingEvents.addDeleteHandler((carId) {
      _removeLocal(carId);
    });
  }

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
    _ensureDeleteHandlerRegistered();
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

      final without = items.where((e) => !_entryMatchesId(e, listingId)).toList();

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

  static bool _entryMatchesId(Map<String, dynamic> entry, String listingId) {
    if (listingMatchesId(entry, listingId)) return true;
    final snap = entry['snapshot'];
    if (snap is Map) {
      return listingMatchesId(
        Map<String, dynamic>.from(snap.cast<String, dynamic>()),
        listingId,
      );
    }
    return false;
  }

  /// Local entries only (no network).
  static Future<List<Map<String, dynamic>>> loadLocalDisplayList() async {
    _ensureDeleteHandlerRegistered();
    final local = await _loadLocal();
    if (local.isEmpty) return [];
    final hydrated = await _hydrateIds(local);
    return hydrated.isNotEmpty ? hydrated : local;
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

  static String _carKey(Map<String, dynamic> car) {
    final id = listingPrimaryId(car);
    return id.isNotEmpty ? id : (car['id'] ?? '').toString();
  }

  static List<Map<String, dynamic>> _mergeById(
    List<Map<String, dynamic>> primary,
    List<Map<String, dynamic>> secondary,
  ) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final car in [...primary, ...secondary]) {
      final key = _carKey(car);
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      out.add(car);
      if (out.length >= maxItems) break;
    }
    return out;
  }

  /// Server list merged with local cache (newest first).
  static Future<List<Map<String, dynamic>>> loadMerged() async {
    _ensureDeleteHandlerRegistered();
    final localDisplay = await loadLocalDisplayList();

    await _ensureAuth();
    final token = ApiService.accessToken ?? TokenStore.token;

    if (token == null || token.isEmpty) {
      return localDisplay;
    }

    try {
      final data = await ApiService.getRecentlyViewed(page: 1, perPage: maxItems);
      final raw = data['cars'];
      if (raw is List) {
        final serverCars = raw
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
            .toList();
        if (serverCars.isNotEmpty) {
          return _mergeById(serverCars, localDisplay);
        }
      }
    } catch (_) {}

    return localDisplay;
  }

  static Future<void> _removeLocal(String listingId) async {
    final id = listingId.trim();
    if (id.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final items = _decode(sp.getString(localKey));
      final kept = items.where((e) => !_entryMatchesId(e, id)).toList();
      await sp.setString(localKey, json.encode(kept));
    } catch (_) {}
  }

  static Future<void> _clearLocal() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(localKey);
    } catch (_) {}
  }

  /// Remove one listing from local cache and server (when logged in).
  static Future<void> removeOne(String listingId) async {
    final id = listingId.trim();
    if (id.isEmpty) return;
    await _removeLocal(id);
    try {
      await _ensureAuth();
      final token = ApiService.accessToken ?? TokenStore.token;
      if (token == null || token.isEmpty) return;
      await ApiService.deleteRecentlyViewedListing(id);
    } catch (_) {}
  }

  /// Clear all recently viewed history locally and on the server.
  static Future<void> clearAll() async {
    await _clearLocal();
    try {
      await _ensureAuth();
      final token = ApiService.accessToken ?? TokenStore.token;
      if (token == null || token.isEmpty) return;
      await ApiService.clearRecentlyViewed();
    } catch (_) {}
  }
}
