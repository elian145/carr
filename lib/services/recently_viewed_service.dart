import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import '../shared/prefs/account_local_data.dart';
import '../shared/listings/listing_events.dart';
import '../shared/listings/listing_identity.dart';
import '../features/listing/listing_mappers.dart';
import '../shared/debug/app_log.dart';

/// The account (and authentication session) an operation STARTED under.
///
/// The local list lives under one global key that is re-scoped on every
/// account switch (see `AccountLocalData`), so an operation that outlives its
/// session must not write there or hand its result to the next account.
class _ViewScope {
  _ViewScope()
      : epoch = ApiService.sessionEpoch,
        owner = ApiService.currentAccountId;

  final int epoch;

  /// Validated account id, or `null` for a guest / unidentified session.
  final String? owner;

  bool get isCurrent => ApiService.sessionEpoch == epoch;
}

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

  static Future<void> _ensureAuth() => ApiService.ensureSessionLoaded();

  static List<Map<String, dynamic>> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = json.decode(raw);
      return listingMapsFromApiList(list);
    } catch (e, st) { logNonFatal(e, st); 
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
    final scope = _ViewScope();

    await _recordLocal(id, scope, snapshot: snapshot);

    try {
      await _ensureAuth();
      // The view belongs to the session it was made in; never report it as a
      // different account.
      if (!scope.isCurrent) return;
      final token = ApiService.accessToken;
      if (token == null || token.isEmpty) return;
      await ApiService.recordListingView(id);
    } catch (e, st) { logNonFatal(e, st); }
  }

  static Future<void> _recordLocal(
    String listingId,
    _ViewScope scope, {
    Map<String, dynamic>? snapshot,
  }) async {
    try {
      await AccountLocalData.runForOwner(
        scope.owner,
        (sp) => _recordLocalInto(sp, listingId, snapshot),
        stillValid: () => scope.isCurrent,
      );
    } catch (e, st) { logNonFatal(e, st); }
  }

  static Future<void> _recordLocalInto(
    SharedPreferences sp,
    String listingId,
    Map<String, dynamic>? snapshot,
  ) async {
    {
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
    }
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
  static Future<List<Map<String, dynamic>>> loadLocalDisplayList() =>
      _loadLocalDisplayList(_ViewScope());

  static Future<List<Map<String, dynamic>>> _loadLocalDisplayList(
    _ViewScope scope,
  ) async {
    _ensureDeleteHandlerRegistered();
    final local = await _loadLocal(scope);
    if (!scope.isCurrent) return [];
    if (local.isEmpty) return [];
    final hydrated = await _hydrateIds(local, scope);
    // Hydration is slow network work: if the account changed meanwhile, the
    // result belongs to the previous account and must not be handed on.
    if (!scope.isCurrent) return [];
    if (hydrated.isNotEmpty) return hydrated;
    // Re-read prefs: [_hydrateIds] may have pruned definitive 404 stubs.
    // Falling back to the pre-hydrate [local] list would resurrect them.
    // Bare id stubs that only failed transiently remain for the next pass.
    final again = await _loadLocal(scope);
    return scope.isCurrent ? again : [];
  }

  static Future<List<Map<String, dynamic>>> _loadLocal([_ViewScope? scope]) async {
    final s = scope ?? _ViewScope();
    final items = await AccountLocalData.withOwner<List<Map<String, dynamic>>>(
          s.owner,
          (sp) async => _decode(sp.getString(localKey)),
          stillValid: () => s.isCurrent,
        ) ??
        const <Map<String, dynamic>>[];
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
    _ViewScope scope,
  ) async {
    final out = <Map<String, dynamic>>[];
    for (final stub in stubs) {
      if (!scope.isCurrent) return out;
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
      } on ApiException catch (e, st) {
        // Expected: deleted / not-visible listing. Drop the stale local
        // stub quietly — do not report as a Sentry error. Other failures
        // (5xx, auth, transport) still go through [logNonFatal].
        if (e.statusCode == 404) {
          await _removeLocal(id, scope);
          continue;
        }
        logNonFatal(e, st);
      } catch (e, st) {
        logNonFatal(e, st);
      }
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
    final scope = _ViewScope();
    final localDisplay = await _loadLocalDisplayList(scope);
    if (!scope.isCurrent) return const <Map<String, dynamic>>[];

    await _ensureAuth();
    if (!scope.isCurrent) return const <Map<String, dynamic>>[];
    final token = ApiService.accessToken;

    if (token == null || token.isEmpty) {
      return localDisplay;
    }

    try {
      final data = await ApiService.getRecentlyViewed(page: 1, perPage: maxItems);
      if (!scope.isCurrent) return const <Map<String, dynamic>>[];
      final raw = data['cars'];
      if (raw is List) {
        final serverCars = listingMapsFromApiList(raw);
        if (serverCars.isNotEmpty) {
          return _mergeById(serverCars, localDisplay);
        }
      }
    } catch (e, st) { logNonFatal(e, st); }

    return scope.isCurrent ? localDisplay : const <Map<String, dynamic>>[];
  }

  static Future<void> _removeLocal(String listingId, [_ViewScope? scope]) async {
    final id = listingId.trim();
    if (id.isEmpty) return;
    final s = scope ?? _ViewScope();
    try {
      await AccountLocalData.runForOwner(s.owner, (sp) async {
        final items = _decode(sp.getString(localKey));
        final kept = items.where((e) => !_entryMatchesId(e, id)).toList();
        await sp.setString(localKey, json.encode(kept));
      }, stillValid: () => s.isCurrent);
    } catch (e, st) { logNonFatal(e, st); }
  }

  static Future<void> _clearLocal(_ViewScope scope) async {
    try {
      await AccountLocalData.runForOwner(
        scope.owner,
        (sp) async {
          await sp.remove(localKey);
        },
        stillValid: () => scope.isCurrent,
      );
    } catch (e, st) { logNonFatal(e, st); }
  }

  /// Remove one listing from local cache and server (when logged in).
  static Future<void> removeOne(String listingId) async {
    final id = listingId.trim();
    if (id.isEmpty) return;
    final scope = _ViewScope();
    await _removeLocal(id, scope);
    try {
      await _ensureAuth();
      if (!scope.isCurrent) return;
      final token = ApiService.accessToken;
      if (token == null || token.isEmpty) return;
      await ApiService.deleteRecentlyViewedListing(id);
    } catch (e, st) { logNonFatal(e, st); }
  }

  /// Clear all recently viewed history locally and on the server.
  static Future<void> clearAll() async {
    final scope = _ViewScope();
    await _clearLocal(scope);
    try {
      await _ensureAuth();
      if (!scope.isCurrent) return;
      final token = ApiService.accessToken;
      if (token == null || token.isEmpty) return;
      await ApiService.clearRecentlyViewed();
    } catch (e, st) { logNonFatal(e, st); }
  }
}
