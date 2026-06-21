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

  test('adminDealersPending GET returns dealers envelope', () async {
    final res = await ApiService.adminDealersPending();
    expect(res['dealers'], isA<List>());
  });

  test('adminApproveDealer POST succeeds on mock API', () async {
    final res = await ApiService.adminApproveDealer('dealer_pending_1');
    expect(res['message'], isNotNull);
  });

  test('adminRejectDealer POST succeeds on mock API', () async {
    final res = await ApiService.adminRejectDealer(
      'dealer_pending_1',
      reason: 'Incomplete paperwork',
    );
    expect(res['message'], isNotNull);
  });
}
