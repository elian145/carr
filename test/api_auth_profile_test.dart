import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/services/api_service.dart';

import 'fake_api_server.dart';

void main() {
  setUpAll(() async {
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    FakeApiServer.expectBearer(null);
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

  test('changePassword POST returns success message', () async {
    final result = await ApiService.changePassword(
      currentPassword: 'Aa123456!',
      newPassword: 'Bb123456!',
    );
    expect(result['message'], isNotEmpty);
  });

  test('updateProfile PUT returns updated user envelope', () async {
    final result = await ApiService.updateProfile({'first_name': 'Updated'});
    expect(result['message'], isNotEmpty);
    expect(result['user'], isA<Map>());
    expect((result['user'] as Map)['first_name'], 'Updated');
  });

  test('confirmSignup POST returns tokens', () async {
    final result = await ApiService.confirmSignup('signup-token-abc');
    expect(result['message'], isNotEmpty);
    expect(result['access_token'], isNotEmpty);
  });

  test('getProfile sends stored access token in Authorization header', () async {
    FakeApiServer.expectBearer('test_access_token');
    final profile = await ApiService.getProfile();
    expect(profile['username'], 'testuser');
  });
}
