import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/features/listing/car_details_listing_fields.dart';

void main() {
  group('listingFirstNonEmpty', () {
    test('returns first non-empty key', () {
      expect(
        listingFirstNonEmpty({'a': '', 'b': 'ok'}, ['a', 'b']),
        'ok',
      );
    });

    test('returns null when all empty', () {
      expect(listingFirstNonEmpty({'a': ''}, ['a', 'b']), isNull);
    });
  });

  group('sellerPhoneRawForContact', () {
    test('prefers contact_phone on listing', () {
      expect(
        sellerPhoneRawForContact({
          'contact_phone': '+9647700000000',
          'seller': {'phone': '111'},
        }),
        '+9647700000000',
      );
    });

    test('falls back to seller phone', () {
      expect(
        sellerPhoneRawForContact({
          'seller': {'phone_number': '07701234567'},
        }),
        '07701234567',
      );
    });
  });

  group('hasDialableSellerPhone', () {
    test('true when digits present', () {
      expect(
        hasDialableSellerPhone({'contact_phone': '+964 770 000 0000'}),
        isTrue,
      );
    });

    test('false when no digits', () {
      expect(hasDialableSellerPhone({'contact_phone': 'n/a'}), isFalse);
    });
  });

  group('relatedListingQueryBands', () {
    test('computes +/- bands', () {
      final bands = relatedListingQueryBands({'price': 10000, 'year': 2020});
      expect(bands.priceMin, 8500);
      expect(bands.priceMax, 11500);
      expect(bands.yearMin, 2018);
      expect(bands.yearMax, 2022);
    });
  });

  group('listingIdentityIds', () {
    test('collects route and listing ids', () {
      final ids = listingIdentityIds(
        {'id': '1', 'public_id': 'pub-1'},
        'route-id',
      );
      expect(ids, {'route-id', '1', 'pub-1'});
    });
  });
}
