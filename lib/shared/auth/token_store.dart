import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../shared/debug/app_log.dart';

/// Single source of truth for the app auth token.
///
/// Both API services and UI should use this instead of duplicating storage logic.
/// Uses [FlutterSecureStorage] default options (strong encryption on Android/iOS).
///
/// On secure-storage failure (e.g. some sideload iOS builds), [save] / [saveRefresh]
/// keep tokens in memory only for the current session; they are lost on app restart.
class TokenStore {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static String? _token;
  static String? _refreshToken;

  /// In-memory only — set by tests that stub HTTP (no secure-storage plugins).
  @visibleForTesting
  static bool testMode = false;

  @visibleForTesting
  static void resetForTests() {
    _token = null;
    _refreshToken = null;
  }

  static String? get token => _token;
  static String? get refreshToken => _refreshToken;

  static Future<void> load() async {
    if (testMode) return;
    try {
      _token = await _storage.read(key: 'auth_token');
      _refreshToken = await _storage.read(key: 'auth_refresh_token');
    } catch (e, st) { logNonFatal(e, st); 
      _token = null;
      _refreshToken = null;
    }
  }

  static Future<void> save(String? token) async {
    final t = (token ?? '').trim();
    if (testMode) {
      _token = t.isEmpty ? null : t;
      return;
    }
    try {
      if (t.isEmpty) {
        await _storage.delete(key: 'auth_token');
        _token = null;
      } else {
        await _storage.write(key: 'auth_token', value: t);
        _token = t;
      }
    } catch (e, st) { logNonFatal(e, st); 
      // Best-effort: on some sideload iOS builds, keychain operations can fail.
      _token = t.isEmpty ? null : t;
    }
  }

  static Future<void> saveRefresh(String? token) async {
    final t = (token ?? '').trim();
    if (testMode) {
      _refreshToken = t.isEmpty ? null : t;
      return;
    }
    try {
      if (t.isEmpty) {
        await _storage.delete(key: 'auth_refresh_token');
        _refreshToken = null;
      } else {
        await _storage.write(key: 'auth_refresh_token', value: t);
        _refreshToken = t;
      }
    } catch (e, st) { logNonFatal(e, st); 
      _refreshToken = t.isEmpty ? null : t;
    }
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
    try {
      return await _storage.read(key: 'push_token');
    } catch (e, st) {
      logNonFatal(e, st, 'TokenStore.readPushToken');
      return _pushToken;
    }
  }

  static String? _pushToken;

  static Future<void> savePushToken(String? token) async {
    final t = (token ?? '').trim();
    if (testMode) {
      _pushToken = t.isEmpty ? null : t;
      return;
    }
    try {
      if (t.isEmpty) {
        await _storage.delete(key: 'push_token');
        _pushToken = null;
      } else {
        await _storage.write(key: 'push_token', value: t);
        _pushToken = t;
      }
    } catch (e, st) {
      logNonFatal(e, st, 'TokenStore.savePushToken');
      _pushToken = t.isEmpty ? null : t;
    }
  }
}
