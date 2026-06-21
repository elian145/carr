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

  test('reportUser POST succeeds on mock API', () async {
    await ApiService.reportUser(
      'seller_1',
      reason: 'Spam',
      details: 'Test details',
    );
  });

  test('reportListing POST succeeds on mock API', () async {
    await ApiService.reportListing(
      'list_car_1',
      reason: 'Misleading listing',
    );
  });

  test('blockUser and unblockUser POST succeed on mock API', () async {
    await ApiService.blockUser('seller_1');
    await ApiService.unblockUser('seller_1');
  });

  test('getBlockedUsers GET returns blocked_users list', () async {
    final blocked = await ApiService.getBlockedUsers();
    expect(blocked, isA<List<String>>());
  });

  test('adminListReports GET returns reports envelope', () async {
    final result = await ApiService.adminListReports(
      status: 'pending',
      type: 'all',
    );
    expect(result['reports'], isA<List>());
  });

  test('adminUpdateUserReport PATCH returns report envelope', () async {
    final result = await ApiService.adminUpdateUserReport(
      1,
      status: 'resolved',
    );
    expect(result['report'], isA<Map>());
    expect(result['report']['status'], 'resolved');
  });

  test('adminUpdateListingReport PATCH returns report envelope', () async {
    final result = await ApiService.adminUpdateListingReport(
      1,
      status: 'dismissed',
    );
    expect(result['report'], isA<Map>());
    expect(result['report']['type'], 'listing');
  });
}
