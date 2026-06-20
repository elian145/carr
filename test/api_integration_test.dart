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

  test('createCar POST returns wrapped car payload', () async {
    final result = await ApiService.createCar({
      'brand': 'toyota',
      'model': 'camry',
      'year': 2020,
      'price': 15000,
      'location': 'Erbil',
    });
    expect(result['car'], isA<Map<String, dynamic>>());
    expect(result['car']['id'], 'mock_car_new');
  });

  test('toggleFavorite POST marks listing favorited', () async {
    final result = await ApiService.toggleFavorite('list_car_1');
    expect(result['is_favorited'], isTrue);
  });

  test('createSavedSearch returns saved_search envelope', () async {
    final result = await ApiService.createSavedSearch(
      name: 'Camry deals',
      filters: {'brand': 'toyota', 'model': 'camry'},
    );
    expect(result['saved_search'], isA<Map<String, dynamic>>());
    expect(result['saved_search']['id'], isNotEmpty);
  });

  test('updateCar PUT returns updated car', () async {
    final result = await ApiService.updateCar('list_car_1', {
      'price': 12000,
    });
    expect(result['car'], isA<Map<String, dynamic>>());
    expect(result['car']['brand'], 'toyota');
  });

  test('getCars GET returns list envelope with sample car', () async {
    final result = await ApiService.getCars();
    expect(result['cars'], isA<List>());
    expect((result['cars'] as List).length, 1);
  });

  test('getCars with brand filter returns pagination envelope', () async {
    final result = await ApiService.getCars(page: 1, perPage: 10, brand: 'toyota');
    expect(result['cars'], isA<List>());
    expect(result['pagination'], isA<Map>());
  });

  test('isCarFavorited GET reads favorite status envelope', () async {
    final favorited = await ApiService.isCarFavorited('list_car_1');
    expect(favorited, isA<bool>());
  });
}
