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

  test('getDealerProfile returns dealer envelope', () async {
    final result = await ApiService.getDealerProfile('dealer_test_1');
    final dealer = result['dealer'];
    expect(dealer, isA<Map>());
    expect((dealer as Map)['dealership_name'], 'Test Dealer');
    expect(result['listings'], isA<List>());
  });

  test('searchDealers returns paginated dealers list', () async {
    final result = await ApiService.searchDealers(page: 1, perPage: 5);
    expect(result['dealers'], isA<List>());
    expect(result['pagination'], isA<Map>());
  });
}
