import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/services/analytics_service.dart';
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

  test('getUserListingsAnalytics reads empty analytics list from mock API', () async {
    final rows = await AnalyticsService.getUserListingsAnalytics();
    expect(rows, isEmpty);
  });

  test('trackView POST succeeds against mock analytics endpoint', () async {
    await AnalyticsService.trackView('list_car_1');
  });
}
