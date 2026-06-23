import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/features/sell/sell_currency_convert.dart';

void main() {
  group('convertSellListingPrice', () {
    test('converts USD to IQD', () {
      expect(
        convertSellListingPrice(r'$100', 'USD', 'IQD'),
        'IQD 142000',
      );
    });

    test('converts IQD to USD', () {
      expect(
        convertSellListingPrice('IQD 14200', 'IQD', 'USD'),
        r'$10',
      );
    });

    test('returns input when currencies match', () {
      expect(
        convertSellListingPrice(r'$500', 'USD', 'USD'),
        r'$500',
      );
    });
  });
}
