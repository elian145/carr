import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import '../shared/debug/app_log.dart';

/// Local cache + server sync for saved searches.
class SavedSearchService {
  static List<Map<String, dynamic>> _decodeLocal(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = json.decode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
          .toList();
    } catch (e, st) { logNonFatal(e, st); 
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

  // ---------------------------------------------------------------------
  // Per-account local storage (F-34)
  //
  // Saved searches used to live under ONE global key, so whoever signed in
  // next inherited -- and then synced to their own server account -- the
  // previous user's searches. Local data is now keyed by the verified account
  // id (JWT `sub`, confirmed against /auth/me). The old global key is NEVER
  // read as data: it has no owner, so it is deleted rather than adopted.
  // ---------------------------------------------------------------------

  /// Former global key. Only ever deleted, never read.
  static const String legacyLocalKey = 'saved_searches_v1';

  static const String _ownedKeyPrefix = 'saved_searches_v2:';

  static String localKeyForOwner(String ownerId) => '$_ownedKeyPrefix$ownerId';

  static bool _legacyPurged = false;

  /// Deletes the pre-isolation global key. Safe to call repeatedly.
  static Future<void> purgeLegacyUnowned() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (sp.containsKey(legacyLocalKey)) {
        await sp.remove(legacyLocalKey);
      }
      _legacyPurged = true;
    } catch (e, st) {
      logNonFatal(e, st);
    }
  }

  static Future<void> _ensureLegacyPurged() async {
    if (_legacyPurged) return;
    await purgeLegacyUnowned();
  }

  @visibleForTesting
  static void debugResetLegacyPurgeFlag() => _legacyPurged = false;

  /// Account that currently owns local saved-search data, or null when
  /// signed out / identity unverified.
  static String? get currentOwnerId => ApiService.currentAccountId;

  /// Removes everything stored for [ownerId] (account deletion).
  static Future<void> purgeOwner(String ownerId) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(localKeyForOwner(ownerId));
  }

  /// Reads [ownerId]'s local list (defaults to the current account). Signed
  /// out or unverified => empty: another account's cache is never returned.
  static Future<List<Map<String, dynamic>>> loadLocal({String? ownerId}) async {
    // The owner is fixed BEFORE the first await: a sign-in during the legacy
    // purge must not make this read the next account's cache.
    final owner = ownerId ?? currentOwnerId;
    await _ensureLegacyPurged();
    if (owner == null || owner.isEmpty) return [];
    final sp = await SharedPreferences.getInstance();
    return dedupeByFilters(_decodeLocal(sp.getString(localKeyForOwner(owner))));
  }

  /// Persists [items] for [ownerId] (defaults to the current account). A null
  /// owner means there is no safe place to store them, so nothing is written.
  static Future<void> persistLocal(
    List<Map<String, dynamic>> items, {
    String? ownerId,
  }) async {
    final owner = ownerId ?? currentOwnerId;
    if (owner == null || owner.isEmpty) return;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      localKeyForOwner(owner),
      json.encode(dedupeByFilters(items)),
    );
    final hook = debugAfterLocalPersist;
    if (hook != null) await hook();
  }

  /// Test-only barrier awaited right after a local write completes, so a test
  /// can switch accounts at exactly that asynchronous point. Never set in
  /// production.
  @visibleForTesting
  static Future<void> Function()? debugAfterLocalPersist;

  /// Load saved searches for the signed-in account only: its own local cache
  /// merged with its own server list. Never returns another account's data
  /// and never syncs unowned data.
  ///
  /// The result belongs to [session] (captured by the caller before it
  /// awaited anything; by default the session this call starts in). It is
  /// checked against that session immediately before it is returned: if the
  /// account changed meanwhile the result is dropped (`[]`), never handed to
  /// a caller that now belongs to someone else.
  static Future<List<Map<String, dynamic>>> loadMerged({
    AuthSessionSnapshot? session,
  }) async {
    final AuthSessionSnapshot s;
    try {
      s = session ?? await ApiService.beginSession();
    } on ApiSessionChangedException {
      return [];
    }
    await _ensureLegacyPurged();
    if (!s.authenticated || !ApiService.isSessionCurrent(s)) return [];
    final owner = s.accountId;

    try {
      if (owner == null) {
        // Authenticated but ownership unverifiable: use the server list only,
        // store nothing locally, upload nothing.
        final res = await ApiService.getSavedSearches();
        if (!ApiService.isSessionCurrent(s)) return [];
        return _fromServerResponse(res);
      }
      final local = await loadLocal(ownerId: owner);
      if (!ApiService.isSessionCurrent(s)) return [];
      try {
        if (local.isNotEmpty) {
          final synced = await ApiService.syncSavedSearches(local);
          if (!ApiService.isSessionCurrent(s)) return [];
          final merged = _fromServerResponse(synced);
          await persistLocal(merged, ownerId: owner);
          return ApiService.isSessionCurrent(s) ? merged : [];
        }
        final res = await ApiService.getSavedSearches();
        if (!ApiService.isSessionCurrent(s)) return [];
        final server = _fromServerResponse(res);
        await persistLocal(server, ownerId: owner);
        return ApiService.isSessionCurrent(s) ? server : [];
      } on ApiSessionChangedException {
        return [];
      } catch (e, st) {
        logNonFatal(e, st);
        return ApiService.isSessionCurrent(s) ? local : [];
      }
    } on ApiSessionChangedException {
      return [];
    } catch (e, st) {
      logNonFatal(e, st);
      return [];
    }
  }

  /// Saves/updates the search for [filters] under the current account
  /// (replaces the Home page's direct access to the old global key) and pushes
  /// it to the server. Returns the stored payload.
  ///
  /// The whole operation belongs to the session it was started in: if the
  /// account changes at any await, nothing further is stored or uploaded, and
  /// the server push never carries another account's credentials.
  static Future<Map<String, dynamic>> upsertFromFilters({
    required Map<String, dynamic> filters,
    required String name,
    bool forceNotify = false,
  }) async {
    final current = normalizeFilters(filters);
    final AuthSessionSnapshot session;
    try {
      session = await ApiService.beginSession();
    } on ApiSessionChangedException {
      // A different account signed in while this save was starting: it is
      // not that account's search. Nothing is stored or uploaded.
      return _newPayload(
        name: name,
        filters: current,
        notify: forceNotify,
      );
    }
    final owner = session.accountId;
    final raw = owner == null
        ? <Map<String, dynamic>>[]
        : await loadLocal(ownerId: owner);

    Map<String, dynamic>? existing;
    for (final item in raw) {
      final f = item['filters'] is Map
          ? Map<String, dynamic>.from(
              (item['filters'] as Map).cast<String, dynamic>(),
            )
          : <String, dynamic>{};
      if (filtersEqual(f, current)) {
        existing = Map<String, dynamic>.from(item);
        break;
      }
    }
    final notify = forceNotify ? true : (existing?['notify'] as bool? ?? false);
    final now = DateTime.now().toIso8601String();
    final payload = existing != null
        ? {
            ...existing,
            'name': name,
            'filters': current,
            'notify': notify,
            'created_at': now,
          }
        : _newPayload(name: name, filters: current, notify: notify);

    final withoutDup = raw
        .where(
          (e) => !filtersEqual(
            e['filters'] is Map
                ? Map<String, dynamic>.from(
                    (e['filters'] as Map).cast<String, dynamic>(),
                  )
                : null,
            current,
          ),
        )
        .toList();
    withoutDup.insert(0, payload);
    final deduped = dedupeByFilters(withoutDup);
    // Only write while the session that produced this save is still current.
    if (owner != null && ApiService.isSessionCurrent(session)) {
      await persistLocal(deduped, ownerId: owner);
    }
    // ...and only upload while it still is: after the awaits above the
    // signed-in account may be a different one, and A's search must never be
    // synced with B's credentials (nor a guest's with any account's).
    if (deduped.isNotEmpty &&
        session.authenticated &&
        ApiService.isSessionCurrent(session)) {
      unawaited(
        pushItemToServer(
          Map<String, dynamic>.from(deduped.first),
          session: session,
        ),
      );
    }
    return payload;
  }

  static Map<String, dynamic> _newPayload({
    required String name,
    required Map<String, dynamic> filters,
    required bool notify,
  }) =>
      <String, dynamic>{
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'name': name,
        'filters': filters,
        'notify': notify,
        'created_at': DateTime.now().toIso8601String(),
      };
  static bool _isServerId(String id) {
    final s = id.trim();
    return s.contains('-') && s.length >= 32;
  }

  /// Uploads [item]. Bound to [session] (default: the session current at
  /// call time): if that session has ended, nothing is sent -- an item that
  /// belongs to one account is never uploaded with another account's token.
  static Future<void> pushItemToServer(
    Map<String, dynamic> item, {
    AuthSessionSnapshot? session,
  }) async {
    final s = session ?? ApiService.captureSession();
    if (!s.authenticated || !ApiService.isSessionCurrent(s)) return;

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
        if (created is Map && ApiService.isSessionCurrent(s)) {
          item['id'] = (created['id'] ?? id).toString();
        }
      }
    } catch (e, st) { logNonFatal(e, st); }
  }

  static Future<void> deleteOnServer(
    String id, {
    AuthSessionSnapshot? session,
  }) async {
    if (!_isServerId(id)) return;
    final s = session ?? ApiService.captureSession();
    if (!s.authenticated || !ApiService.isSessionCurrent(s)) return;
    try {
      await ApiService.deleteSavedSearch(id);
    } catch (e, st) { logNonFatal(e, st); }
  }
}
