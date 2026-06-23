import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/features/sell/sell_brand_slug.dart';

void main() {
  group('sellBrandSlug', () {
    test('lowercases and hyphenates spaces', () {
      expect(sellBrandSlug('Toyota'), 'toyota');
      expect(sellBrandSlug('Land Rover'), 'land-rover');
    });

    test('strips non-alphanumeric characters', () {
      expect(sellBrandSlug('Mercedes-Benz'), 'mercedes-benz');
      expect(sellBrandSlug('  BMW  '), 'bmw');
    });
  });
}
