import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/debug/app_log.dart';

/// Single source of truth for the app auth token.
///
/// Uses [FlutterSecureStorage] (Keychain / EncryptedSharedPreferences).
///
/// On iOS Sideloadly / free-account installs, Keychain writes can fail. When that
/// happens we mirror tokens into [SharedPreferences] so the session survives
/// app restart (still lost on uninstall). Prefer Keychain when it works; never
/// add `keychain-access-groups` for Sideloadly IPAs (see [docs/IOS_TESTING.md]).
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
    // Sideload / broken Keychain: keep session across restarts via prefs.
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
