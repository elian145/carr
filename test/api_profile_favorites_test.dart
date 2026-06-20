import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/services/api_service.dart';

import 'fake_api_server.dart';

void main() {
  setUpAll(() async {
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    await ApiService.setTokens(
      accessToken: 'test_access_token',
      refreshToken: 'test_refresh_token',
    );
  });

  tearDown(() async {
    await ApiService.clearTokens();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  test('sendOtpLegacy hits /auth/send_otp', () async {
    final result = await ApiService.sendOtpLegacy(phone: '+9647700000000');
    expect(result['sent'], isA<bool>());
  });

  test('getProfile returns bare user from /auth/me', () async {
    final profile = await ApiService.getProfile();
    expect(profile['username'], 'testuser');
    expect(profile['user'], isNull);
  });

  test('getFavorites returns cars list envelope', () async {
    final favorites = await ApiService.getFavorites();
    expect(favorites['cars'], isA<List>());
  });

  test('getMyListings uses paginated envelope', () async {
    final listings = await ApiService.getMyListings();
    expect(listings['cars'], isA<List>());
    expect(listings['pagination'], isA<Map>());
  });
}
