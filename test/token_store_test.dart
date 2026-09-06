import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/shared/auth/token_store.dart';

/// Deterministic fake for [FlutterSecureStoragePlatform.instance].
///
/// H-07 tests need to force secure-storage success/failure independent of
/// whatever real backend (iOS Simulator Keychain, Windows DPAPI, libsecret,
/// ...) happens to be available on the machine/CI running `flutter test`.
class _FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> store = {};
  bool throwOnWrite = false;
  bool throwOnRead = false;

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    if (throwOnWrite) {
      throw PlatformException(code: 'fake_write_failure', message: 'simulated secure storage failure');
    }
    store[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    if (throwOnRead) {
      throw PlatformException(code: 'fake_read_failure', message: 'simulated secure storage failure');
    }
    return store[key];
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async {
    return store.containsKey(key);
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    if (throwOnWrite) {
      throw PlatformException(code: 'fake_write_failure', message: 'simulated secure storage failure');
    }
    store.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    return Map<String, String>.of(store);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    store.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FlutterSecureStoragePlatform originalPlatform;
  late _FakeSecureStoragePlatform fakePlatform;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TokenStore.testMode = false;
    TokenStore.resetForTests();
    // Safe default: matches the real ALLOW_INSECURE_TOKEN_FALLBACK dart-define
    // default (false) unless a test explicitly opts into the Sideloadly path.
    TokenStore.allowInsecureFallbackForTests = false;
    originalPlatform = FlutterSecureStoragePlatform.instance;
    fakePlatform = _FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = fakePlatform;
  });

  tearDown(() {
    TokenStore.testMode = true;
    TokenStore.resetForTests();
    TokenStore.allowInsecureFallbackForTests = false;
    FlutterSecureStoragePlatform.instance = originalPlatform;
  });

  test('testMode keeps tokens in memory only', () async {
    TokenStore.testMode = true;
    await TokenStore.save('access');
    await TokenStore.saveRefresh('refresh');
    expect(TokenStore.token, 'access');
    expect(TokenStore.refreshToken, 'refresh');
    TokenStore.resetForTests();
    expect(TokenStore.token, isNull);
  });

  group('H-07: official builds (ALLOW_INSECURE_TOKEN_FALLBACK=false)', () {
    test('secure storage works: token is stored and read back securely, no plaintext mirror is ever written', () async {
      TokenStore.allowInsecureFallbackForTests = false;

      await TokenStore.save('secure-access');
      await TokenStore.saveRefresh('secure-refresh');

      // The secure backend actually received the values...
      expect(fakePlatform.store['auth_token'], 'secure-access');
      expect(fakePlatform.store['auth_refresh_token'], 'secure-refresh');

      // ...and no plaintext mirror was ever written.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('token_store_fallback_auth_token'), isNull);
      expect(prefs.getString('token_store_fallback_auth_refresh_token'), isNull);

      // Simulate a cold start: drop in-memory state, reload from storage.
      TokenStore.resetForTests();
      await TokenStore.load();
      expect(TokenStore.token, 'secure-access');
      expect(TokenStore.refreshToken, 'secure-refresh');
    });

    test('secure storage write fails: token is NOT written to plaintext SharedPreferences', () async {
      TokenStore.allowInsecureFallbackForTests = false;
      fakePlatform.throwOnWrite = true;

      await TokenStore.save('should-not-persist-anywhere-durable');
      await TokenStore.saveRefresh('should-not-persist-anywhere-durable-refresh');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('token_store_fallback_auth_token'), isNull);
      expect(prefs.getString('token_store_fallback_auth_refresh_token'), isNull);

      // The in-memory session for the CURRENT run still works (fail closed,
      // not a crash) — it just won't survive a relaunch.
      expect(TokenStore.token, 'should-not-persist-anywhere-durable');
      expect(TokenStore.refreshToken, 'should-not-persist-anywhere-durable-refresh');
    });

    test('secure storage read throws + a stale plaintext fallback exists: fallback is NOT trusted and is purged', () async {
      TokenStore.allowInsecureFallbackForTests = false;
      SharedPreferences.setMockInitialValues({
        'token_store_fallback_auth_token': 'stale_plaintext_access',
        'token_store_fallback_auth_refresh_token': 'stale_plaintext_refresh',
      });
      TokenStore.resetForTests();
      fakePlatform.throwOnRead = true;

      await TokenStore.load();

      // Never authenticated off a plaintext value.
      expect(TokenStore.token, isNull);
      expect(TokenStore.refreshToken, isNull);

      // The stale plaintext keys are purged, not merely ignored.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('token_store_fallback_auth_token'), isNull);
      expect(prefs.getString('token_store_fallback_auth_refresh_token'), isNull);
    });

    test('secure storage read returns empty + a stale plaintext fallback exists: fallback is NOT trusted and is purged', () async {
      TokenStore.allowInsecureFallbackForTests = false;
      SharedPreferences.setMockInitialValues({
        'token_store_fallback_auth_token': 'stale_plaintext_access',
      });
      TokenStore.resetForTests();
      // fakePlatform.store has no 'auth_token' entry -> read() resolves to
      // null without throwing (a healthy backend that simply never wrote it).

      await TokenStore.load();

      expect(TokenStore.token, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('token_store_fallback_auth_token'), isNull);
    });
  });

  group('H-07: Sideloadly QA builds (ALLOW_INSECURE_TOKEN_FALLBACK=true)', () {
    test('secure storage write fails: legacy M-19 plaintext fallback WRITE behavior is preserved', () async {
      TokenStore.allowInsecureFallbackForTests = true;
      fakePlatform.throwOnWrite = true;

      await TokenStore.save('fallback_access');
      await TokenStore.saveRefresh('fallback_refresh');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('token_store_fallback_auth_token'), 'fallback_access');
      expect(prefs.getString('token_store_fallback_auth_refresh_token'), 'fallback_refresh');
    });

    test('prefs fallback restores session when seeded (M-19) — legacy READ behavior is preserved', () async {
      TokenStore.allowInsecureFallbackForTests = true;
      // Simulate a prior Keychain failure that wrote the durable prefs mirror.
      SharedPreferences.setMockInitialValues({
        'token_store_fallback_auth_token': 'fallback_access',
        'token_store_fallback_auth_refresh_token': 'fallback_refresh',
      });
      TokenStore.resetForTests();
      fakePlatform.throwOnRead = true;

      await TokenStore.load();

      expect(TokenStore.token, 'fallback_access');
      expect(TokenStore.refreshToken, 'fallback_refresh');
    });
  });

  test('clear() deletes both the secure entry and the plaintext fallback entry', () async {
    TokenStore.allowInsecureFallbackForTests = true;
    // Seed leftovers directly in both backends (as if a previous session had
    // written to each), without going through load()/save() first.
    fakePlatform.store['auth_token'] = 'secure_leftover';
    fakePlatform.store['auth_refresh_token'] = 'secure_leftover_refresh';
    fakePlatform.store['push_token'] = 'secure_push_leftover';
    SharedPreferences.setMockInitialValues({
      'token_store_fallback_auth_token': 'plaintext_leftover',
      'token_store_fallback_auth_refresh_token': 'plaintext_leftover_refresh',
      'token_store_fallback_push_token': 'plaintext_push_leftover',
    });
    TokenStore.resetForTests();

    await TokenStore.clear();

    expect(TokenStore.token, isNull);
    expect(TokenStore.refreshToken, isNull);
    expect(fakePlatform.store.containsKey('auth_token'), isFalse);
    expect(fakePlatform.store.containsKey('auth_refresh_token'), isFalse);
    expect(fakePlatform.store.containsKey('push_token'), isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('token_store_fallback_auth_token'), isNull);
    expect(prefs.getString('token_store_fallback_auth_refresh_token'), isNull);
    expect(prefs.getString('token_store_fallback_push_token'), isNull);
  });
}
