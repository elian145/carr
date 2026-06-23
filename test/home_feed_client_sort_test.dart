import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/features/home/home_feed_client_sort.dart';

void main() {
  final sample = [
    {'price': '20000', 'year': '2018', 'mileage': '50000', 'created_at': '2024-01-01'},
    {'price': '15000', 'year': '2020', 'mileage': '30000', 'created_at': '2024-06-01'},
    {'price': '25000', 'year': '2016', 'mileage': '80000', 'created_at': '2023-12-01'},
  ];

  group('homeFeedClientSortedListings', () {
    test('sorts by price ascending', () {
      final out = homeFeedClientSortedListings(sample, 'price_asc');
      expect(out.map((c) => c['price']).toList(), ['15000', '20000', '25000']);
    });

    test('sorts by year descending', () {
      final out = homeFeedClientSortedListings(sample, 'year_desc');
      expect(out.map((c) => c['year']).toList(), ['2020', '2018', '2016']);
    });

    test('returns copy unchanged for unknown sort key', () {
      final out = homeFeedClientSortedListings(sample, 'unknown');
      expect(out, isNot(same(sample)));
      expect(out.map((c) => c['price']).toList(),
          sample.map((c) => c['price']).toList());
    });
  });
}
