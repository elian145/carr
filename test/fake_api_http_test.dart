import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/services/api_service.dart';

import 'fake_api_server.dart';

void main() {
  setUpAll(() async {
    await FakeApiServer.ensureStarted();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  test('fake API mock client is bound during tests', () async {
    expect(ApiService.boundTestHttpClient, isNotNull);
  });

  test('getChats returns sample conversation from mock API', () async {
    await ApiService.setTokens(
      accessToken: 'test_access_token',
      refreshToken: 'test_refresh_token',
    );
    final chats = await ApiService.getChats().timeout(const Duration(seconds: 2));
    expect(chats.length, 1);
    expect(chats.first['car_id'], 'list_car_1');
  });
}
