import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/shared/auth/token_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TokenStore.testMode = false;
    TokenStore.resetForTests();
  });

  tearDown(() {
    TokenStore.testMode = true;
    TokenStore.resetForTests();
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

  test('prefs fallback restores session when seeded (M-19)', () async {
    // Simulate a prior Keychain failure that wrote the durable prefs mirror.
    SharedPreferences.setMockInitialValues({
      'token_store_fallback_auth_token': 'fallback_access',
      'token_store_fallback_auth_refresh_token': 'fallback_refresh',
    });
    TokenStore.resetForTests();

    await TokenStore.load();

    expect(TokenStore.token, 'fallback_access');
    expect(TokenStore.refreshToken, 'fallback_refresh');
  });
}
