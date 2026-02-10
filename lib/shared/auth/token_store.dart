import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Single source of truth for the app auth token.
///
/// Both API services and UI should use this instead of duplicating storage logic.
class TokenStore {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static String? _token;

  static String? get token => _token;

  static Future<void> load() async {
    try {
      _token = await _storage.read(key: 'auth_token');
    } catch (_) {
      _token = null;
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

  static Future<void> clear() => save(null);
}
