import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/models/chat_message.dart';
import 'package:car_listing_app/models/listing.dart';
import 'package:car_listing_app/models/user_profile.dart';
import 'package:car_listing_app/features/listing/listing_mappers.dart';
import 'package:car_listing_app/shared/listings/listing_share_urls.dart';

void main() {
  test('ListingSummary round-trip', () {
    const json = {
      'id': 42,
      'title': 'Test Car',
      'brand': 'Toyota',
      'model': 'Camry',
      'year': 2020,
      'price': 15000,
      'currency': 'USD',
    };
    final summary = ListingSummary.fromJson(json);
    expect(summary.id, '42');
    expect(summary.toJson()['title'], 'Test Car');
  });

  test('UserProfile fromJson', () {
    final user = UserProfile.fromJson({
      'id': 1,
      'username': 'alice',
      'first_name': 'Alice',
      'is_verified': true,
    });
    expect(user.displayName, 'Alice');
    expect(user.isVerified, isTrue);
  });

  test('ChatMessage fromJson', () {
    final msg = ChatMessage.fromJson({
      'id': 'm1',
      'conversation_id': 'c1',
      'sender_id': 'u1',
      'body': 'Hello',
    });
    expect(msg.body, 'Hello');
    expect(msg.toJson()['conversation_id'], 'c1');
  });

  test('listingDeepLink builds carzo scheme URL', () {
    final link = listingDeepLink('abc123');
    expect(link, contains('carzo://'));
    expect(link, contains('abc123'));
  });

  test('listingMapsFromApiResponse parses list and cars wrapper', () {
    final rows = listingMapsFromApiResponse([
      {'id': 1, 'title': 'Camry', 'brand': 'Toyota', 'price': 12000},
      {'car_id': 'x2', 'name': 'Civic'},
      'skip',
      {},
    ]);
    expect(rows.length, 2);
    expect(rows.first['id'], '1');
    expect(rows.first['title'], 'Camry');

    final wrapped = listingMapsFromApiResponse({
      'cars': [
        {'id': 'w1', 'title': 'Wrapped'},
      ],
    });
    expect(wrapped.length, 1);
    expect(wrapped.first['id'], 'w1');
  });

  test('listingMapsFromFavoritesResponse handles cars and favorites keys', () {
    final fromCars = listingMapsFromFavoritesResponse({
      'cars': [
        {'id': '1', 'title': 'A'},
      ],
    });
    expect(fromCars.length, 1);

    final fromFavorites = listingMapsFromFavoritesResponse({
      'favorites': [
        {'car_id': '2', 'title': 'B'},
      ],
    });
    expect(fromFavorites.length, 1);
    expect(fromFavorites.first['id'], '2');
  });
}
