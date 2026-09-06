import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/config.dart' show kAllowInsecureTokenFallback;
import '../../shared/debug/app_log.dart';

/// Single source of truth for the app auth token.
///
/// Uses [FlutterSecureStorage] (Keychain / EncryptedSharedPreferences) as the
/// only durable store in official builds.
///
/// H-07 / M-19: on iOS Sideloadly / free-account installs, Keychain writes can
/// fail. Historically (M-19) we mirrored tokens into plaintext
/// [SharedPreferences] so the session survived app restart. That plaintext
/// mirror is now gated behind [kAllowInsecureTokenFallback] — a compile-time
/// dart-define (`ALLOW_INSECURE_TOKEN_FALLBACK`, default **false**) set ONLY
/// by the Sideloadly Codemagic workflow. Official App Store / Play Store /
/// TestFlight builds never set it, so on those builds:
///   - a secure-storage write failure never falls back to plaintext prefs;
///   - a secure-storage read failure/empty result never trusts a plaintext
///     value, and any pre-existing plaintext fallback keys are purged;
///   - the normal "not authenticated" / login flow handles the gap — this
///     never crashes.
/// Never add `keychain-access-groups` for Sideloadly IPAs (see
/// [docs/IOS_TESTING.md]).
class TokenStore {
  static const _kAccess = 'auth_token';
  static const _kRefresh = 'auth_refresh_token';
  static const _kPush = 'push_token';
  static const _kPrefsAccess = 'token_store_fallback_auth_token';
  static const _kPrefsRefresh = 'token_store_fallback_auth_refresh_token';
  static const _kPrefsPush = 'token_store_fallback_push_token';

  /// Device-only Keychain after first unlock — works for sideload without
  /// `keychain-access-groups`. Avoid changing accessibility after ship (reads
  /// won't match older items).
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  static String? _token;
  static String? _refreshToken;
  static String? _pushToken;

  /// In-memory only — set by tests that stub HTTP (no secure-storage plugins).
  @visibleForTesting
  static bool testMode = false;

  /// Test-only override for [kAllowInsecureTokenFallback].
  ///
  /// [kAllowInsecureTokenFallback] is a compile-time constant (dart-define),
  /// so it can't vary within a single test binary. This override lets tests
  /// exercise both the flag-disabled (official build) and flag-enabled
  /// (Sideloadly) code paths. Defaults to the real compile-time value;
  /// production code must never set this.
  @visibleForTesting
  static bool allowInsecureFallbackForTests = kAllowInsecureTokenFallback;

  static bool get _allowInsecureFallback => allowInsecureFallbackForTests;

  @visibleForTesting
  static void resetForTests() {
    _token = null;
    _refreshToken = null;
    _pushToken = null;
  }

  static String? get token => _token;
  static String? get refreshToken => _refreshToken;

  static Future<void> load() async {
    if (testMode) return;
    _token = await _readDurable(_kAccess, _kPrefsAccess);
    _refreshToken = await _readDurable(_kRefresh, _kPrefsRefresh);
  }

  static Future<void> save(String? token) async {
    final t = (token ?? '').trim();
    if (testMode) {
      _token = t.isEmpty ? null : t;
      return;
    }
    _token = t.isEmpty ? null : t;
    await _writeDurable(_kAccess, _kPrefsAccess, _token);
  }

  static Future<void> saveRefresh(String? token) async {
    final t = (token ?? '').trim();
    if (testMode) {
      _refreshToken = t.isEmpty ? null : t;
      return;
    }
    _refreshToken = t.isEmpty ? null : t;
    await _writeDurable(_kRefresh, _kPrefsRefresh, _refreshToken);
  }

  static Future<void> clear() async {
    if (testMode) {
      resetForTests();
      return;
    }
    await save(null);
    await saveRefresh(null);
    await savePushToken(null);
  }

  static Future<String?> readPushToken() async {
    if (testMode) return _pushToken;
    final v = await _readDurable(_kPush, _kPrefsPush);
    _pushToken = v;
    return v;
  }

  static Future<void> savePushToken(String? token) async {
    final t = (token ?? '').trim();
    if (testMode) {
      _pushToken = t.isEmpty ? null : t;
      return;
    }
    _pushToken = t.isEmpty ? null : t;
    await _writeDurable(_kPush, _kPrefsPush, _pushToken);
  }

  static Future<String?> _readDurable(String secureKey, String prefsKey) async {
    try {
      final fromSecure = await _storage.read(key: secureKey);
      if (fromSecure != null && fromSecure.trim().isNotEmpty) {
        // Prefer Keychain; drop prefs mirror so we don't keep a weaker copy.
        await _prefsDelete(prefsKey);
        return fromSecure.trim();
      }
    } catch (e, st) {
      logNonFatal(e, st, 'TokenStore.secureRead:$secureKey');
    }

    if (!_allowInsecureFallback) {
      // H-07: official builds never treat a plaintext value as a valid
      // credential — not even one already sitting on disk from a previous
      // app version or a flag-enabled build. Purge it so it can't be read
      // again; callers see `null` and fall back to the normal
      // "not authenticated" / login flow (never a crash).
      await _prefsDelete(prefsKey);
      return null;
    }

    // Sideloadly QA only (ALLOW_INSECURE_TOKEN_FALLBACK=true): preserve the
    // existing M-19 behavior so a broken Keychain doesn't drop the session.
    return _prefsRead(prefsKey);
  }

  static Future<void> _writeDurable(
    String secureKey,
    String prefsKey,
    String? value,
  ) async {
    final ok = await _secureWrite(secureKey, value);
    if (ok) {
      await _prefsDelete(prefsKey);
      return;
    }

    if (!_allowInsecureFallback) {
      // H-07: official builds must never persist tokens in plaintext.
      // Secure storage failed — leave nothing durable on disk. The
      // in-memory value set by save()/saveRefresh() still lets the current
      // app session keep working; on the next cold start the read path
      // above will find nothing and the user simply has to log in again
      // (fail closed, no crash).
      await _prefsDelete(prefsKey);
      return;
    }

    // Sideload / broken Keychain (ALLOW_INSECURE_TOKEN_FALLBACK=true only):
    // keep session across restarts via prefs (M-19).
    if (value == null || value.isEmpty) {
      await _prefsDelete(prefsKey);
    } else {
      await _prefsWrite(prefsKey, value);
    }
  }

  /// Returns true when Keychain/EncryptedSharedPreferences accepted the write.
  static Future<bool> _secureWrite(String key, String? value) async {
    Future<void> once() async {
      if (value == null || value.isEmpty) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: value);
      }
    }

    try {
      await once();
      return true;
    } catch (e, st) {
      logNonFatal(e, st, 'TokenStore.secureWrite:$key');
      // Retry after delete — common when accessibility / duplicate item conflicts.
      try {
        await _storage.delete(key: key);
        if (value != null && value.isNotEmpty) {
          await _storage.write(key: key, value: value);
        }
        return true;
      } catch (e2, st2) {
        logNonFatal(e2, st2, 'TokenStore.secureWriteRetry:$key');
        return false;
      }
    }
  }

  static Future<String?> _prefsRead(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = (prefs.getString(key) ?? '').trim();
      return v.isEmpty ? null : v;
    } catch (e, st) {
      logNonFatal(e, st, 'TokenStore.prefsRead:$key');
      return null;
    }
  }

  static Future<void> _prefsWrite(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (e, st) {
      logNonFatal(e, st, 'TokenStore.prefsWrite:$key');
    }
  }

  static Future<void> _prefsDelete(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (e, st) {
      logNonFatal(e, st, 'TokenStore.prefsDelete:$key');
    }
  }
}
