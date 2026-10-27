import '../debug/app_log.dart';
import '../prefs/account_local_data.dart';

/// Fan-out point for authentication transitions (login, logout, token clear,
/// account switch, app start) so every in-memory cache and on-device store
/// that holds account data can reset or re-scope itself.
///
/// Order for every transition (see `ApiService`):
/// 1. the session epoch is bumped synchronously and [notifySessionChanged]
///    runs (in-memory caches must drop their data immediately);
/// 2. on-device stores are re-scoped by [activate] (which awaits
///    `AccountLocalData.activate`);
/// 3. [activate] then tells activation listeners (e.g. the comparison list)
///    to reload from the newly active owner's storage.
class AccountScope {
  AccountScope._();

  static final List<void Function()> _sessionChangedListeners =
      <void Function()>[];
  static final List<void Function(String? owner)> _activatedListeners =
      <void Function(String? owner)>[];

  /// Synchronous: drop in-memory account data NOW.
  static void addSessionChangedListener(void Function() listener) {
    if (!_sessionChangedListeners.contains(listener)) {
      _sessionChangedListeners.add(listener);
    }
  }

  static void removeSessionChangedListener(void Function() listener) {
    _sessionChangedListeners.remove(listener);
  }

  /// Called after on-device storage has been re-scoped for the new owner.
  static void addActivatedListener(void Function(String? owner) listener) {
    if (!_activatedListeners.contains(listener)) {
      _activatedListeners.add(listener);
    }
  }

  static void removeActivatedListener(void Function(String? owner) listener) {
    _activatedListeners.remove(listener);
  }

  static int _generation = 0;

  /// Increments on every authentication transition. Async writers capture it
  /// before awaiting and drop the write if it moved, so a save started under
  /// one account can never land in another account's storage.
  static int get generation => _generation;

  static void notifySessionChanged() {
    _generation++;
    for (final l in List<void Function()>.of(_sessionChangedListeners)) {
      try {
        l();
      } catch (e, st) {
        logNonFatal(e, st, 'AccountScope.sessionChanged');
      }
    }
  }

  /// Re-scopes on-device data to [owner] and tells activation listeners.
  ///
  /// [generation] is the value of [AccountScope.generation] captured
  /// synchronously when the authentication transition this activation belongs
  /// to happened (defaults to "now"). If a NEWER transition has happened
  /// since -- before the queue reached this activation, or while it ran -- the
  /// activation is dropped and its listeners are never called: the newer
  /// transition activates its own owner, and a stale owner must never be
  /// delivered after it.
  static Future<void> activate(String? owner, {int? generation}) async {
    final gen = generation ?? _generation;
    if (gen != _generation) return;
    try {
      await AccountLocalData.activate(
        owner,
        stillValid: () => gen == _generation,
      );
    } catch (e, st) {
      logNonFatal(e, st, 'AccountScope.activate');
    }
    if (gen != _generation) return;
    for (final l in List<void Function(String? owner)>.of(_activatedListeners)) {
      try {
        l(owner);
      } catch (e, st) {
        logNonFatal(e, st, 'AccountScope.activated');
      }
    }
  }
}
