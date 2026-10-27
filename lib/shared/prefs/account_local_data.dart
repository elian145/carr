import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../debug/app_log.dart';

/// F-34 / decision 10: account-scoped isolation for on-device keys that are
/// read and written directly through their legacy global names in many places
/// (sell drafts, comparison list, recently viewed, optimistic owner media).
///
/// Instead of rewriting every call site, the *values* under these global keys
/// always belong to exactly one owner at a time ([_markerKey]). Whenever the
/// authenticated account changes (login, logout, account switch, app start),
/// [activate] moves the previous owner's values into a private per-owner
/// stash and brings the new owner's stash back. Consequences:
///
/// * A -> logout -> B: B starts with an empty set (never A's data).
/// * B -> logout -> A: A gets A's own data back (legitimate data preserved).
/// * Guest -> account: data created while logged out belongs to the *guest*
///   bucket and is **never** adopted by the account that signs in next. On a
///   shared device the next account could be a different person, and nothing
///   proves the guest and that person are the same (a guest's recently viewed
///   cars / comparison list is private browsing behaviour too). The guest
///   values wait in the guest stash and reappear when the device is signed
///   out again.
/// * Legacy data with no recorded owner (written by builds before this
///   change) is **quarantined**, never adopted by whichever account happens
///   to sign in first. It stays unreachable and is deleted after
///   [legacyQuarantineMaxAge].
///
/// Keys that carry their own explicit owner scoping (saved searches, chat
/// pending sends, favorites cache) do not use this mechanism.
class AccountLocalData {
  AccountLocalData._();

  /// Global keys whose value belongs to the active owner.
  static const List<String> scopedKeys = <String>[
    'recently_viewed_local_v1',
    'comparison_cars',
    'owner_optimistic_media_v1',
    // Pre-migration record of an interrupted listing upload. No current build
    // writes it (see `PendingSellSubmissionService`); only unowned leftovers
    // from old builds can exist, and those are quarantined, never adopted.
    'legacy_sell_pending_media_v1',
    // One-shot hand-off of a tapped saved search's filters to the home feed
    // (SavedSearchHomeBridge): it carries that account's saved search, so it
    // must not be consumed by the next account's home feed.
    'home_apply_filters_once_v1',
    'home_pending_saved_search_fetch_v1',
    'legacy_sell_draft_current_step_v1',
    'legacy_sell_draft_snapshot_v1',
    'legacy_sell_draft_archive_v1',
    'legacy_sell_draft_step1_v1',
    'legacy_sell_draft_step2_v1',
    'legacy_sell_draft_step3_v1',
    'legacy_sell_draft_step4_v1',
  ];

  /// Which owner currently occupies [scopedKeys]. Absent => legacy/unowned.
  static const String markerKey = 'account_local_data_owner_v1';

  /// Marker value meaning "nobody is signed in".
  static const String guestOwner = '';

  static const String legacyOwner = '__legacy_unowned__';
  static const String _stashPrefix = 'acct_stash_v1';
  static const String _legacyStampKey = 'acct_stash_v1:legacy_quarantined_at';
  static const Duration legacyQuarantineMaxAge = Duration(days: 30);

  // Operations are serialized with a waiter queue instead of chaining onto a
  // long-lived static Future: a Future created in one (test) zone schedules its
  // listeners in that zone, which would deadlock a later FakeAsync zone.
  static bool _busy = false;
  static final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  static Future<T> _serialized<T>(Future<T> Function() op) async {
    if (_busy) {
      final turn = Completer<void>();
      _waiters.add(turn);
      await turn.future; // ownership of [_busy] is handed over to us
    } else {
      _busy = true;
    }
    try {
      return await op();
    } finally {
      if (_waiters.isNotEmpty) {
        _waiters.removeFirst().complete();
      } else {
        _busy = false;
      }
    }
  }

  /// Test hook: forget any operation left half-way by a previous test.
  @visibleForTesting
  static void debugReset() {
    _busy = false;
    _waiters.clear();
  }

  static String stashKey(String owner, String key) =>
      '$_stashPrefix:$owner:$key';

  /// Makes [owner] (`null` = nobody signed in) the owner of [scopedKeys].
  /// Idempotent and serialized; safe to call from any transition.
  ///
  /// [stillValid], when given, is re-checked once this activation reaches the
  /// front of the queue; a superseded activation (a newer authentication
  /// transition happened while it waited) is dropped, because the newer
  /// transition activates its own owner.
  static Future<void> activate(
    String? owner, {
    bool Function()? stillValid,
  }) async {
    try {
      await _serialized(() async {
        if (stillValid != null && !stillValid()) return;
        await _activate(owner ?? guestOwner);
      });
    } catch (e, st) {
      logNonFatal(e, st, 'AccountLocalData.activate');
    }
  }

  static Future<void> _activate(String target) async {
    final sp = await SharedPreferences.getInstance();
    final current = sp.getString(markerKey);
    await _expireLegacy(sp);
    if (current == target) return;

    final from = current ?? legacyOwner;

    // 1. Move the outgoing owner's values (guest included) to its stash.
    final values = <String, Object?>{
      for (final k in scopedKeys) k: sp.get(k),
    };
    if (from == legacyOwner) {
      await sp.setString(
        _legacyStampKey,
        DateTime.now().toIso8601String(),
      );
    }
    for (final k in scopedKeys) {
      final v = values[k];
      await _write(sp, stashKey(from, k), v);
      await sp.remove(k);
    }

    // 2. Bring the incoming owner's stash back.
    for (final k in scopedKeys) {
      final sk = stashKey(target, k);
      if (!sp.containsKey(sk)) continue;
      await _write(sp, k, sp.get(sk));
      await sp.remove(sk);
    }
    await sp.setString(markerKey, target);
  }

  static Future<void> _write(
    SharedPreferences sp,
    String key,
    Object? value,
  ) async {
    if (value == null) {
      await sp.remove(key);
    } else if (value is String) {
      await sp.setString(key, value);
    } else if (value is List<String>) {
      await sp.setStringList(key, value);
    } else if (value is bool) {
      await sp.setBool(key, value);
    } else if (value is int) {
      await sp.setInt(key, value);
    } else if (value is double) {
      await sp.setDouble(key, value);
    }
  }

  static Future<void> _expireLegacy(SharedPreferences sp) async {
    final stamp = DateTime.tryParse(sp.getString(_legacyStampKey) ?? '');
    if (stamp == null) return;
    if (DateTime.now().difference(stamp) < legacyQuarantineMaxAge) return;
    for (final k in scopedKeys) {
      await sp.remove(stashKey(legacyOwner, k));
    }
    await sp.remove(_legacyStampKey);
  }

  /// Runs [action] on the global [scopedKeys] ONLY IF they currently belong to
  /// [owner] (`null` = guest) and [stillValid] (when given) still holds,
  /// serialized with [activate] / [purgeOwner] so an account switch can never
  /// interleave with it. Returns whether [action] ran.
  ///
  /// This is how a late, asynchronous writer (started under account A) is
  /// stopped from writing into account B's slot of a global key: it names the
  /// owner it started under and is dropped if the keys have moved on.
  /// (Before the first activation of a run the marker is absent; such values
  /// are legacy/unowned and get quarantined by the first [activate], so the
  /// write is allowed.)
  static Future<bool> runForOwner(
    String? owner,
    Future<void> Function(SharedPreferences sp) action, {
    bool Function()? stillValid,
  }) async {
    final ran = await withOwner<bool>(
      owner,
      (sp) async {
        await action(sp);
        return true;
      },
      stillValid: stillValid,
    );
    return ran ?? false;
  }

  /// Like [runForOwner] but returns [action]'s result, or `null` when the
  /// keys do not (or no longer) belong to [owner]. Reads use it too, so a
  /// read can never observe the previous owner's values while an account
  /// switch is still re-scoping the keys (it waits for [activate]).
  static Future<T?> withOwner<T>(
    String? owner,
    Future<T> Function(SharedPreferences sp) action, {
    bool Function()? stillValid,
  }) async {
    try {
      return await _serialized<T?>(() async {
        if (stillValid != null && !stillValid()) return null;
        final sp = await SharedPreferences.getInstance();
        final marker = sp.getString(markerKey);
        if (marker != null && marker != (owner ?? guestOwner)) return null;
        if (stillValid != null && !stillValid()) return null;
        return await action(sp);
      });
    } catch (e, st) {
      logNonFatal(e, st, 'AccountLocalData.withOwner');
      return null;
    }
  }

  /// Deletes every stored value belonging to [owner] (account deletion).
  /// If [owner] currently occupies the global keys, those are cleared too.
  static Future<void> purgeOwner(String owner) async {
    try {
      await _serialized(() async {
      final sp = await SharedPreferences.getInstance();
      for (final k in scopedKeys) {
        await sp.remove(stashKey(owner, k));
      }
      if (sp.getString(markerKey) == owner) {
        for (final k in scopedKeys) {
          await sp.remove(k);
        }
      }
      });
    } catch (e, st) {
      logNonFatal(e, st, 'AccountLocalData.purgeOwner');
    }
  }
}
