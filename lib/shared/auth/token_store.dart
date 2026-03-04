import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Single source of truth for the app auth token.
///
/// Both API services and UI should use this instead of duplicating storage logic.
class TokenStore {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static String? _token;
  static String? _refreshToken;

  static String? get token => _token;
  static String? get refreshToken => _refreshToken;

  static Future<void> load() async {
    try {
      _token = await _storage.read(key: 'auth_token');
      _refreshToken = await _storage.read(key: 'auth_refresh_token');
    } catch (_) {
      _token = null;
      _refreshToken = null;
    }
  }

  static Future<void> save(String? token) async {
    final t = (token ?? '').trim();
    try {
      if (t.isEmpty) {
        await _storage.delete(key: 'auth_token');
        _token = null;
      } else {
        await _storage.write(key: 'auth_token', value: t);
        _token = t;
      }
    } catch (_) {
      // Best-effort: on some sideload iOS builds, keychain operations can fail.
      _token = t.isEmpty ? null : t;
    }
  }

  static Future<void> saveRefresh(String? token) async {
    final t = (token ?? '').trim();
    try {
      if (t.isEmpty) {
        await _storage.delete(key: 'auth_refresh_token');
        _refreshToken = null;
      } else {
        await _storage.write(key: 'auth_refresh_token', value: t);
        _refreshToken = t;
      }
    } catch (_) {
      _refreshToken = t.isEmpty ? null : t;
    }
  }

  static Future<void> clear() async {
    await save(null);
    await saveRefresh(null);
  }
}
